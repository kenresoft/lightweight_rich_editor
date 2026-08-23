import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/attribute_store.dart';
import '../core/editor_document.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/clamp_int.dart';
import '../utils/horizontal_rule.dart';
import '../utils/list_prefix.dart';
import 'document_renderer.dart';
import 'render_theme.dart';

// What kind of marker a `type == null` event represents — composing,
// match-highlight, and selection-highlight events all use `type == null`
// (none are AttributeTypes), so they need their own discriminator.
enum _MarkerKind {
  composing,
  matchHighlight,
  selectionHighlight,
  paragraphBoundary,
  allMatchesHighlight,
}

/// A boundary where the set of active attributes changes: a span
/// starting/ending, the IME composing region starting/ending, or the
/// current search-match highlight starting/ending. Sorting these and
/// sweeping left to right is what turns O(spans × length)
/// character-by-character style resolution into O(spans log spans).
class _StyleEvent {
  final int offset;
  final AttributeType? type;
  final _MarkerKind? markerKind;
  final bool isStart;
  final Object? value;

  const _StyleEvent({
    required this.offset,
    required this.type,
    required this.isStart,
    this.markerKind,
    this.value,
  });
}

/// Renders an [EditorDocument] to a Flutter [TextSpan] — the only place
/// in this library that builds Flutter styling.
///
/// Three stages: [_buildEvents] turns spans (plus the composing range,
/// if any) into a sorted list of start/end boundaries; [renderSpan]
/// sweeps them left to right maintaining a per-[AttributeType] stack of
/// active values; [_resolveStyle] turns "what's active in this segment"
/// into a concrete [TextStyle], once per segment rather than per
/// character.
///
/// List markers (`'- '`, `'3. '`) and horizontal rules (`'---'`) are
/// never injected — they're literal characters the user typed or the
/// importer preserved, styled distinctly here purely presentationally.
/// This renderer feeds a live `TextField` via `TextEditingController
/// .buildTextSpan`, and the rendered span's plain text must match
/// `value.text` exactly, character for character, or caret/selection
/// placement corrupts — so nothing here can add or remove characters.
///
/// Heading size/weight is read from `EditorDocument.paragraphs`
/// (`ParagraphIndex`), not from an `AttributeType.header` span in the
/// event sweep — though those spans still exist in `AttributeStore` and
/// still drive the render cache's invalidation key.
///
/// Results are cached against [AttributeStore.revision] plus the other
/// call inputs, so re-rendering after a selection-only change is a
/// cache hit.
class TextSpanRenderer implements DocumentRenderer<TextSpan> {
  /// Reassigning this (e.g. a dark-mode theme swap) clears the
  /// quantized-line-height cache, which is keyed by font size/weight/
  /// style alone and would otherwise reuse heights computed against the
  /// old [RichTextRenderTheme.lineHeight].
  RichTextRenderTheme get theme => _theme;
  set theme(RichTextRenderTheme value) {
    if (_theme == value) return;
    _theme = value;
    _quantizedLineHeightCache.clear();
  }

  RichTextRenderTheme _theme;

  /// Called when the user taps a link span, with the link's URL.
  void Function(String url)? onTapLink;

  /// Called when the user taps a task-list checkbox glyph, with the
  /// offset of that paragraph's start. `null` (the default) means
  /// checkbox prefixes render but aren't tappable.
  void Function(int paragraphStart)? onToggleCheckbox;

  /// Whether links are interactive (clickable) in the rendered span. In
  /// an editable field this should usually be `false`, so cursor
  /// placement and selection still work on links; the host can still
  /// handle links via long-press (selection toolbar).
  bool interactiveLinks;

  TextSpanRenderer({
    RichTextRenderTheme theme = RichTextRenderTheme.standard,
    this.onTapLink,
    this.onToggleCheckbox,
    this.interactiveLinks = true,
    // ignore: prefer_initializing_formals
  }) : _theme = theme;

  TextSpan? _cachedSpan;
  String? _cachedText;
  int? _cachedRevision;
  int? _cachedParagraphRevision;
  TextStyle? _cachedStyle;
  TextRange? _cachedComposing;
  TextRange? _cachedMatchHighlight;
  TextRange? _cachedSelectionHighlight;
  List<TextRange>? _cachedAllMatches;
  RichTextRenderTheme? _cachedTheme;
  bool? _cachedInteractiveLinks;

  // GestureRecognizers must be explicitly disposed — every rebuild
  // disposes the previous batch before creating a new one, and dispose()
  // cleans up whatever's left when this renderer itself goes away.
  final List<TapGestureRecognizer> _recognizers = [];

  /// Renders with defaults — no base style, no composing region. Enough
  /// for a read-only preview; the live editor should call [renderSpan]
  /// directly so it can pass the current composing range.
  @override
  TextSpan render(EditorDocument document) => renderSpan(document);

  /// Renders `document` to a [TextSpan], applying `style` as the base,
  /// underlining `composingRange` (IME composition feedback), and
  /// painting `matchHighlightRange` with
  /// [RichTextRenderTheme.matchHighlightColor].
  ///
  /// `allMatchesRanges`, if given, paints every other range with
  /// [RichTextRenderTheme.otherMatchesHighlightColor] so the *current*
  /// match stays the one that stands out. For cache-friendliness, pass
  /// the same list instance across calls when the match set hasn't
  /// changed — compared by reference, not deep equality.
  ///
  /// The match highlight is a distinct visual channel from Flutter's
  /// native [TextSelection] highlight: `EditableText` hides its
  /// selection highlight whenever the field loses focus (e.g. the find
  /// bar's own text field taking focus), which would make "jump to next
  /// match" invisible. Baking the highlight into the span itself keeps
  /// it visible regardless of which field has focus.
  TextSpan renderSpan(
    EditorDocument document, {
    TextStyle? style,
    TextRange? composingRange,
    TextRange? matchHighlightRange,
    TextRange? selectionHighlightRange,
    List<TextRange>? allMatchesRanges,
  }) {
    final text = document.text;
    final revision = document.attributeStore.revision;
    final paragraphRevision = document.paragraphs.revision;

    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedRevision == revision &&
        _cachedParagraphRevision == paragraphRevision &&
        _cachedStyle == style &&
        _cachedComposing == composingRange &&
        _cachedMatchHighlight == matchHighlightRange &&
        _cachedSelectionHighlight == selectionHighlightRange &&
        identical(_cachedAllMatches, allMatchesRanges) &&
        _cachedTheme == theme &&
        _cachedInteractiveLinks == interactiveLinks) {
      return _cachedSpan!;
    }

    final span = _render(
      document,
      style,
      composingRange,
      matchHighlightRange,
      selectionHighlightRange,
      allMatchesRanges,
    );

    _cachedSpan = span;
    _cachedText = text;
    _cachedRevision = revision;
    _cachedParagraphRevision = paragraphRevision;
    _cachedStyle = style;
    _cachedComposing = composingRange;
    _cachedMatchHighlight = matchHighlightRange;
    _cachedSelectionHighlight = selectionHighlightRange;
    _cachedAllMatches = allMatchesRanges;
    _cachedTheme = theme;
    _cachedInteractiveLinks = interactiveLinks;
    return span;
  }

  /// Invalidates the cache without changing anything else — call if
  /// `theme` was mutated in place rather than reassigned.
  void invalidateCache() => _cachedSpan = null;

  List<double>? _cachedLineBottoms;
  double? _cachedLineBottomsWidth;
  StrutStyle? _cachedLineBottomsStrut;
  String? _cachedLineBottomsText;
  int? _cachedLineBottomsRevision;
  int? _cachedLineBottomsParagraphRevision;
  TextStyle? _cachedLineBottomsBaseStyle;
  TextHeightBehavior? _cachedLineBottomsHeightBehavior;
  TextDirection? _cachedLineBottomsDirection;

  /// The bottom Y offset (document/unscrolled space) of every actually
  /// *rendered* line, accounting for wrapping and any per-paragraph
  /// font-size difference (headers) — what `RuledLinesPainter` aligns
  /// ruled lines against.
  ///
  /// Built by laying out the same [TextSpan] this renderer produces
  /// through a throwaway [TextPainter] with the same `maxWidth`/
  /// `strutStyle` the real `TextField` uses, so it agrees with where
  /// that field actually renders.
  ///
  /// Cached the same way [renderSpan] is, plus `maxWidth`/`strutStyle`/
  /// `style`. A cache hit returns the *same list instance* as last time
  /// — callers can and should compare by reference for cheap per-frame
  /// checks.
  List<double> lineBottomOffsets(
    EditorDocument document, {
    required double maxWidth,
    TextStyle? style,
    required StrutStyle strutStyle,
    TextHeightBehavior? textHeightBehavior,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final text = document.text;
    final revision = document.attributeStore.revision;
    final paragraphRevision = document.paragraphs.revision;

    if (_cachedLineBottoms != null &&
        _cachedLineBottomsText == text &&
        _cachedLineBottomsRevision == revision &&
        _cachedLineBottomsParagraphRevision == paragraphRevision &&
        _cachedLineBottomsWidth == maxWidth &&
        _cachedLineBottomsStrut == strutStyle &&
        _cachedLineBottomsBaseStyle == style &&
        _cachedLineBottomsHeightBehavior == textHeightBehavior &&
        _cachedLineBottomsDirection == textDirection) {
      return _cachedLineBottoms!;
    }

    final span = renderSpan(document, style: style);
    final painter = TextPainter(
      text: span,
      strutStyle: strutStyle,
      textDirection: textDirection,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: textHeightBehavior,
    )..layout(maxWidth: maxWidth <= 0 ? double.infinity : maxWidth);

    final bottoms = <double>[];
    var y = 0.0;
    for (final line in painter.computeLineMetrics()) {
      y += line.height;
      bottoms.add(y);
    }

    _cachedLineBottoms = bottoms;
    _cachedLineBottomsText = text;
    _cachedLineBottomsRevision = revision;
    _cachedLineBottomsParagraphRevision = paragraphRevision;
    _cachedLineBottomsWidth = maxWidth;
    _cachedLineBottomsStrut = strutStyle;
    _cachedLineBottomsBaseStyle = style;
    _cachedLineBottomsHeightBehavior = textHeightBehavior;
    _cachedLineBottomsDirection = textDirection;
    return bottoms;
  }

  /// The document-space (unscrolled) Y offset of `charOffset`'s glyph —
  /// what a caller scrolling the editor's viewport to bring a specific
  /// character into view needs. Same parallel-[TextPainter] technique
  /// [lineBottomOffsets] uses — pass the same `maxWidth`/`style`/
  /// `strutStyle`/`textHeightBehavior` that field uses.
  ///
  /// Not cached: called only when the current search match actually
  /// changes, not on every frame.
  double offsetYFor(
    EditorDocument document,
    int charOffset, {
    required double maxWidth,
    TextStyle? style,
    required StrutStyle strutStyle,
    TextHeightBehavior? textHeightBehavior,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final span = renderSpan(document, style: style);
    final painter = TextPainter(
      text: span,
      strutStyle: strutStyle,
      textDirection: textDirection,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: textHeightBehavior,
    )..layout(maxWidth: maxWidth <= 0 ? double.infinity : maxWidth);

    final clamped = clampInt(charOffset, 0, document.text.length);
    return painter.getOffsetForCaret(TextPosition(offset: clamped), Rect.zero).dy;
  }

  /// Disposes any tap recognizers still attached to the last rendered
  /// span. Call when the renderer itself is being discarded (e.g. from
  /// `RichEditorController.dispose()`) — normal rebuilds already dispose
  /// the previous batch themselves.
  void dispose() => _disposeRecognizers();

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer? _recognizerFor(String? linkUrl) {
    if (linkUrl == null || onTapLink == null || !interactiveLinks) return null;
    final url = linkUrl;
    final recognizer = TapGestureRecognizer()
      ..onTap = () => onTapLink?.call(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  TapGestureRecognizer? _checkboxRecognizerFor(int paragraphStart) {
    if (onToggleCheckbox == null) return null;
    final recognizer = TapGestureRecognizer()
      ..onTap = () => onToggleCheckbox?.call(paragraphStart);
    _recognizers.add(recognizer);
    return recognizer;
  }

  TextSpan _render(
    EditorDocument document,
    TextStyle? style,
    TextRange? composingRange,
    TextRange? matchHighlightRange,
    TextRange? selectionHighlightRange,
    List<TextRange>? allMatchesRanges,
  ) {
    _disposeRecognizers();

    final text = document.text;
    if (text.isEmpty) return TextSpan(text: text, style: style);

    final length = text.length;
    final hasComposing =
        composingRange != null &&
        composingRange.isValid &&
        composingRange.end > composingRange.start;
    final hasMatchHighlight =
        matchHighlightRange != null &&
        matchHighlightRange.isValid &&
        matchHighlightRange.end > matchHighlightRange.start;
    final hasSelectionHighlight =
        selectionHighlightRange != null &&
        selectionHighlightRange.isValid &&
        selectionHighlightRange.end > selectionHighlightRange.start;
    final hasAllMatches = allMatchesRanges != null && allMatchesRanges.isNotEmpty;

    final spans = document.attributes;
    final hasListPrefix = _containsListPrefix(document);
    final hasHorizontalRule = _containsHorizontalRule(document);
    if (spans.isEmpty &&
        !hasComposing &&
        !hasMatchHighlight &&
        !hasSelectionHighlight &&
        !hasAllMatches &&
        !hasListPrefix &&
        !hasHorizontalRule &&
        !document.paragraphs.hasAnyHeader) {
      return TextSpan(text: text, style: style);
    }

    final events = _buildEvents(
      document,
      spans,
      length,
      hasComposing ? composingRange : null,
      hasMatchHighlight ? matchHighlightRange : null,
      hasSelectionHighlight ? selectionHighlightRange : null,
      hasAllMatches ? allMatchesRanges : null,
    );
    if (events.isEmpty && !hasListPrefix && !hasHorizontalRule) {
      return TextSpan(text: text, style: style);
    }

    return TextSpan(
      style: style,
      children: _buildChildren(document, events, style),
    );
  }

  // Whether any paragraph starts with a literal list prefix — decides
  // whether _render can take its plain-TextSpan fast path. O(paragraphs)
  // via document.paragraphs.records, not a stored field: list-ness has
  // no stable cached representation across applyInsertion/applyDeletion.
  bool _containsListPrefix(EditorDocument document) {
    final text = document.text;
    for (final record in document.paragraphs.records) {
      if (listPrefixLength(text, record.start) > 0) return true;
    }
    return false;
  }

  // Whether any paragraph is a horizontal-rule line — same rationale as
  // _containsListPrefix.
  bool _containsHorizontalRule(EditorDocument document) {
    final text = document.text;
    for (final record in document.paragraphs.records) {
      if (isHorizontalRuleLine(text, record.start, record.end)) return true;
    }
    return false;
  }

  List<_StyleEvent> _buildEvents(
    EditorDocument document,
    List<TextAttribute> spans,
    int length,
    TextRange? composingRange,
    TextRange? matchHighlightRange,
    TextRange? selectionHighlightRange,
    List<TextRange>? allMatchesRanges,
  ) {
    final events = <_StyleEvent>[];

    for (final attr in spans) {
      final start = clampInt(attr.start, 0, length);
      final end = clampInt(attr.end, 0, length);
      if (end <= start) continue;
      events.add(
        _StyleEvent(
          offset: start,
          type: attr.type,
          isStart: true,
          value: attr.value,
        ),
      );
      events.add(
        _StyleEvent(
          offset: end,
          type: attr.type,
          isStart: false,
          value: attr.value,
        ),
      );
    }

    // Forces the sweep to stop at a paragraph start whenever that
    // paragraph's own presentational state (header level, hr-ness, or
    // its own list/checkbox prefix) could plausibly differ from the
    // paragraph before — otherwise a boundary that doesn't coincide with
    // any other event could be skipped, leaving currentHeaderLevel
    // un-refreshed for that paragraph.
    final text = document.text;
    String? previousHeaderLevel;
    var previousIsHorizontalRule = false;
    for (final record in document.paragraphs.records) {
      final isHr = isHorizontalRuleLine(text, record.start, record.end);
      final hasOwnPrefix = !isHr && listPrefixLength(text, record.start) > 0;
      final needsBoundary = record.start > 0 &&
          (record.headerLevel != previousHeaderLevel ||
              isHr != previousIsHorizontalRule ||
              hasOwnPrefix);
      if (needsBoundary) {
        events.add(
          _StyleEvent(
            offset: record.start,
            type: null,
            isStart: true,
            markerKind: _MarkerKind.paragraphBoundary,
          ),
        );
      }
      previousHeaderLevel = record.headerLevel;
      previousIsHorizontalRule = isHr;
    }

    if (composingRange != null) {
      final cs = clampInt(composingRange.start, 0, length);
      final ce = clampInt(composingRange.end, 0, length);
      if (ce > cs) {
        events.add(
          _StyleEvent(
            offset: cs,
            type: null,
            isStart: true,
            markerKind: _MarkerKind.composing,
          ),
        );
        events.add(
          _StyleEvent(
            offset: ce,
            type: null,
            isStart: false,
            markerKind: _MarkerKind.composing,
          ),
        );
      }
    }

    if (matchHighlightRange != null) {
      final ms = clampInt(matchHighlightRange.start, 0, length);
      final me = clampInt(matchHighlightRange.end, 0, length);
      if (me > ms) {
        events.add(
          _StyleEvent(
            offset: ms,
            type: null,
            isStart: true,
            markerKind: _MarkerKind.matchHighlight,
          ),
        );
        events.add(
          _StyleEvent(
            offset: me,
            type: null,
            isStart: false,
            markerKind: _MarkerKind.matchHighlight,
          ),
        );
      }
    }

    if (selectionHighlightRange != null) {
      final ss = clampInt(selectionHighlightRange.start, 0, length);
      final se = clampInt(selectionHighlightRange.end, 0, length);
      if (se > ss) {
        events.add(
          _StyleEvent(
            offset: ss,
            type: null,
            isStart: true,
            markerKind: _MarkerKind.selectionHighlight,
          ),
        );
        events.add(
          _StyleEvent(
            offset: se,
            type: null,
            isStart: false,
            markerKind: _MarkerKind.selectionHighlight,
          ),
        );
      }
    }

    if (allMatchesRanges != null) {
      for (final range in allMatchesRanges) {
        final rs = clampInt(range.start, 0, length);
        final re = clampInt(range.end, 0, length);
        if (re <= rs) continue;
        events.add(
          _StyleEvent(
            offset: rs,
            type: null,
            isStart: true,
            markerKind: _MarkerKind.allMatchesHighlight,
          ),
        );
        events.add(
          _StyleEvent(
            offset: re,
            type: null,
            isStart: false,
            markerKind: _MarkerKind.allMatchesHighlight,
          ),
        );
      }
    }

    events.sort((a, b) {
      final cmp = a.offset.compareTo(b.offset);
      // Process ends before starts at the same offset, so a span that
      // ends exactly where the next begins doesn't momentarily double up.
      return cmp != 0 ? cmp : (a.isStart ? 1 : 0) - (b.isStart ? 1 : 0);
    });

    return events;
  }

  List<TextSpan> _buildChildren(
    EditorDocument document,
    List<_StyleEvent> events,
    TextStyle? baseStyle,
  ) {
    final text = document.text;
    final children = <TextSpan>[];
    final activeValues = {
      for (final type in AttributeType.values) type: <Object?>[],
    };
    var activeComposing = 0;
    var activeMatchHighlight = 0;
    var activeSelectionHighlight = 0;
    var activeAllMatchesHighlight = 0;

    var currentPos = 0;
    var eventIndex = 0;
    String? currentHeaderLevel;
    bool? currentChecked;
    bool currentIsHorizontalRule = false;

    while (currentPos < text.length) {
      while (eventIndex < events.length &&
          events[eventIndex].offset <= currentPos) {
        final event = events[eventIndex];
        if (event.type == null) {
          final delta = event.isStart ? 1 : -1;
          if (event.markerKind == _MarkerKind.matchHighlight) {
            activeMatchHighlight += delta;
          } else if (event.markerKind == _MarkerKind.selectionHighlight) {
            activeSelectionHighlight += delta;
          } else if (event.markerKind == _MarkerKind.allMatchesHighlight) {
            activeAllMatchesHighlight += delta;
          } else if (event.markerKind == _MarkerKind.paragraphBoundary) {
            // No counter needed: this event exists solely to force the
            // loop below to break a segment at this offset.
          } else {
            activeComposing += delta;
          }
        } else if (event.isStart) {
          activeValues[event.type]!.add(event.value);
        } else {
          activeValues[event.type]!.remove(event.value);
        }
        eventIndex++;
      }

      final nextPos = eventIndex < events.length
          ? clampInt(events[eventIndex].offset, 0, text.length)
          : text.length;

      if (nextPos > currentPos) {
        final isParagraphStart =
            currentPos == 0 || text.codeUnitAt(currentPos - 1) == 0x0A;
        if (isParagraphStart) {
          final record = document.paragraphs.paragraphAt(currentPos);
          currentHeaderLevel = record?.headerLevel;
          currentIsHorizontalRule =
              record != null &&
              isHorizontalRuleLine(text, record.start, record.end);
        }
        final prefixLen = isParagraphStart && !currentIsHorizontalRule
            ? listPrefixLength(text, currentPos)
            : 0;
        final prefixEnd = clampInt(currentPos + prefixLen, currentPos, nextPos);
        if (isParagraphStart) {
          currentChecked = prefixLen > 0
              ? checkboxStateOfPrefix(text.substring(currentPos, prefixEnd))
              : null;
        }

        final resolvedStyle = _resolveStyle(
          baseStyle,
          activeValues,
          currentHeaderLevel,
          activeComposing > 0,
          activeMatchHighlight > 0,
          activeSelectionHighlight > 0,
          activeAllMatchesHighlight > 0,
        );

        // A horizontal-rule line is entirely marker — the whole run of
        // hyphens, styled uniformly, with nothing after it to split out.
        if (currentIsHorizontalRule) {
          if (nextPos > currentPos) {
            children.add(
              TextSpan(
                text: text.substring(currentPos, nextPos),
                style: _horizontalRuleStyle(resolvedStyle),
              ),
            );
          }
          currentPos = nextPos;
          continue;
        }

        // The prefix run is styled but otherwise ordinary text — same
        // character count as in the document. No link recognizer on it
        // (a link overlapping a literal '- ' isn't meaningful); a
        // checkbox prefix does get one, since that's the point of it.
        if (prefixEnd > currentPos) {
          children.add(
            TextSpan(
              text: text.substring(currentPos, prefixEnd),
              style: _listPrefixStyle(resolvedStyle),
              recognizer: currentChecked != null
                  ? _checkboxRecognizerFor(currentPos)
                  : null,
            ),
          );
        }

        if (nextPos > prefixEnd) {
          final linkUrl = activeValues[AttributeType.link]!.isEmpty
              ? null
              : activeValues[AttributeType.link]!.last as String?;
          // A checked item's own content gets a line-through on top of
          // whatever else is active, so bold/linked text inside a
          // checked item still reads as struck.
          final contentStyle = currentChecked == true
              ? resolvedStyle.copyWith(
                  decoration: TextDecoration.combine([
                    if (resolvedStyle.decoration != null &&
                        resolvedStyle.decoration != TextDecoration.none)
                      resolvedStyle.decoration!,
                    TextDecoration.lineThrough,
                  ]),
                )
              : resolvedStyle;
          children.add(
            TextSpan(
              text: text.substring(prefixEnd, nextPos),
              style: contentStyle,
              recognizer: _recognizerFor(linkUrl),
            ),
          );
        }
      }
      currentPos = nextPos;
    }

    return children;
  }

  // Keyed by '$fontSize|${fontWeight.value}|$isItalic'.
  final Map<String, double> _quantizedLineHeightCache = {};

  /// The line-box height to target for text at `fontSize`/`fontWeight`/
  /// `isItalic`, rounded *up* to the nearest whole multiple of
  /// [RichTextRenderTheme.lineHeight] rather than forced to exactly one
  /// line. A header's font is often intrinsically taller than one row;
  /// rounding up to a whole number of rows keeps every ruled line still
  /// landing on a multiple of `theme.lineHeight`, while giving the
  /// header's glyphs a box tall enough for them (centered within it via
  /// [TextLeadingDistribution.even] — see where this is consumed in
  /// `RichTextEditor` and [lineBottomOffsets], which need the same
  /// leading distribution).
  double _quantizedLineHeight(
    double fontSize,
    FontWeight fontWeight,
    bool isItalic,
  ) {
    final key = '$fontSize|${fontWeight.value}|$isItalic';
    final cached = _quantizedLineHeightCache[key];
    if (cached != null) return cached;

    // theme.lineHeight is the fallback for anything that doesn't come
    // back as a real, finite, positive measurement — this runs on every
    // styled segment of every render, so a bad result here can't be
    // allowed to take the whole document's layout down with it.
    final result = _measureQuantizedLineHeight(fontSize, fontWeight, isItalic) ?? theme.lineHeight;
    _quantizedLineHeightCache[key] = result;
    return result;
  }

  double? _measureQuantizedLineHeight(
    double fontSize,
    FontWeight fontWeight,
    bool isItalic,
  ) {
    try {
      final probe = TextPainter(
        text: TextSpan(
          text: 'Ág', // tall ascender + descender, a representative worst case
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final metrics = probe.computeLineMetrics();
      if (metrics.length != 1) return null;

      final natural = metrics.single.height;
      if (!natural.isFinite || natural <= 0) return null;
      if (!theme.lineHeight.isFinite || theme.lineHeight <= 0) return null;

      final rows = (natural / theme.lineHeight).ceil().clamp(1, 1000);
      final result = rows * theme.lineHeight;
      return result.isFinite ? result : null;
    } catch (_) {
      return null;
    }
  }

  TextStyle _resolveStyle(
    TextStyle? baseStyle,
    Map<AttributeType, List<Object?>> active,
    String? headerLevel,
    bool isComposing,
    bool isCurrentMatch,
    bool isSelectionHighlight,
    bool isOtherMatch,
  ) {
    bool isActive(AttributeType type) => active[type]!.isNotEmpty;
    Object? topValue(AttributeType type) {
      final stack = active[type]!;
      return stack.isEmpty ? null : stack.last;
    }

    final colorArgb = topValue(AttributeType.color) as int?;
    final sizeValue = topValue(AttributeType.size) as num?;
    final linkUrl = topValue(AttributeType.link) as String?;

    double fontSize = baseStyle?.fontSize ?? theme.baseFontSize;
    FontWeight fontWeight = isActive(AttributeType.bold)
        ? FontWeight.bold
        : (baseStyle?.fontWeight ?? FontWeight.normal);

    if (headerLevel == 'h1') {
      fontSize = theme.h1FontSize;
      fontWeight = FontWeight.bold;
    } else if (headerLevel == 'h2') {
      fontSize = theme.h2FontSize;
      fontWeight = FontWeight.bold;
    } else if (sizeValue != null) {
      fontSize = sizeValue.toDouble();
    }

    final decorations = <TextDecoration>[
      if (isActive(AttributeType.underline) || isComposing || linkUrl != null)
        TextDecoration.underline,
      if (isActive(AttributeType.strikethrough)) TextDecoration.lineThrough,
    ];

    final isCode = isActive(AttributeType.code);
    final isItalic = isActive(AttributeType.italic);

    return (baseStyle ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: _quantizedLineHeight(fontSize, fontWeight, isItalic) / fontSize,
      fontStyle: isItalic
          ? FontStyle.italic
          : (baseStyle?.fontStyle ?? FontStyle.normal),
      color: colorArgb != null
          ? Color(colorArgb)
          : (linkUrl != null ? theme.linkColor : baseStyle?.color),
      // Current match and selection highlight take priority; any other
      // search match comes next, still distinct from ordinary formatting.
      backgroundColor: isCurrentMatch
          ? theme.matchHighlightColor
          : (isSelectionHighlight
                ? theme.linkColor.withValues(alpha: 0.3)
                : (isOtherMatch
                      ? theme.otherMatchesHighlightColor
                      : (isActive(AttributeType.highlight)
                            ? theme.highlightColor
                            : (isCode
                                  ? theme.codeBackgroundColor
                                  : baseStyle?.backgroundColor)))),
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      fontFamily: isCode ? theme.codeFontFamily : baseStyle?.fontFamily,
    );
  }

  // Styling for a literal list-prefix run — layers the theme's marker
  // color/weight on top of the already-resolved style for that position.
  TextStyle _listPrefixStyle(TextStyle segmentStyle) {
    return segmentStyle.copyWith(
      color: theme.listMarkerColor,
      fontWeight: FontWeight.w600,
    );
  }

  // Styling for a horizontal-rule line. Shares listMarkerColor
  // deliberately — both are muted, structural marks, not prose.
  TextStyle _horizontalRuleStyle(TextStyle segmentStyle) {
    return segmentStyle.copyWith(
      color: theme.listMarkerColor,
      fontWeight: FontWeight.w300,
      letterSpacing: 3.0,
    );
  }
}
