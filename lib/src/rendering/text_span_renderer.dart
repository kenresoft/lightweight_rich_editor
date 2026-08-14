import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/attribute_store.dart';
import '../core/editor_document.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/clamp_int.dart';
import '../utils/list_prefix.dart';
import 'document_renderer.dart';
import 'render_theme.dart';

/// What kind of marker a `type == null` event represents — composing
/// events, match-highlight events, and selection-highlight events all use
/// `type == null` (none are [AttributeType]s), so they need their own
/// discriminator to be tracked as separate counters during the sweep.
///
/// Not to be confused with list markers (bullet/number prefixes), which
/// this renderer no longer generates — see the removal note below.
enum _MarkerKind { composing, matchHighlight, selectionHighlight, paragraphBoundary }

/// A boundary where the set of active attributes changes: a span
/// starting/ending, the IME composing region starting/ending, or the
/// current search-match highlight starting/ending. Sorting these and
/// sweeping left to right is what turns O(spans × length)
/// character-by-character style resolution into O(spans log spans).
class _StyleEvent {
  final int offset;
  final AttributeType? type; // null means this is a marker event — see markerKind
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
/// in this library that builds Flutter styling. Everything upstream
/// (`EditorDocument`, `AttributeStore`, `EditingEngine`, `HistoryManager`,
/// commands) is Flutter-free by construction; this class is where that
/// data finally becomes pixels.
///
/// Three stages, matching the target architecture's "event generation,
/// style stack, style resolution, TextSpan generation, caching":
/// 1. [_buildEvents] turns spans (+ the composing range, if any) into a
///    sorted list of start/end boundaries.
/// 2. [renderSpan] sweeps those boundaries left to right, maintaining a
///    per-[AttributeType] stack of currently-active values.
/// 3. [_resolveStyle] turns "what's active in this segment" into a
///    concrete [TextStyle], once per segment rather than once per
///    character.
///
/// This renderer previously injected "virtual" list-marker text (bullet
/// dots, numbers) into the rendered [TextSpan] that had no corresponding
/// characters in the document. That's since been removed: this class
/// feeds a live, editable `TextField` via `TextEditingController
/// .buildTextSpan`, and Flutter requires the rendered span's plain text
/// to match the controller's `value.text` exactly, character for
/// character — `RenderEditable` maps a `TextPosition` in the rendered
/// paragraph straight onto a document offset with no translation layer.
/// Text injected here that isn't in the document silently corrupts caret
/// placement and selection on every line after the injection point. See
/// the removal notes on [AttributeType] for the full rationale.
///
/// List-looking lines aren't lost, though: if a paragraph's own text
/// literally starts with `'- '`, `'* '`, `'+ '`, or `'N. '` (typed by
/// the user, or preserved as-is on import — see [listPrefixLength]),
/// that prefix is styled distinctly here purely presentationally. It's
/// the same character count in as out, so it can't touch the caret
/// invariant above; it's just picking a different [TextStyle] for text
/// that was always going to be rendered anyway.
///
/// Heading size/weight is read from `EditorDocument.paragraphs`
/// (`ParagraphIndex`) rather than from an `AttributeType.header` span in
/// the event sweep below — the first consumer switched over as part of
/// the block-architecture migration (see the design notes and
/// `EditingEngine`'s dual-write call sites). `AttributeType.header`
/// spans still exist in `AttributeStore` and still drive the render
/// cache's invalidation key (`AttributeStore.revision`); they're just no
/// longer what decides the rendered font size here.
///
/// Every paragraph start also gets a synthetic sweep event (see
/// `_MarkerKind.paragraphBoundary`) purely to force the sweep to stop
/// there — without it, a paragraph boundary that didn't happen to
/// coincide with any *other* attribute's start/end could be skipped
/// over entirely as part of a larger segment between two unrelated
/// events, meaning `currentHeaderLevel` would never be re-queried for
/// that paragraph even though `ParagraphIndex.headerLevel` was correct
/// the whole time. This was the actual cause of "header data is right
/// but the paragraph never visibly changes" — not a caching issue
/// (`_cachedParagraphRevision` below is still correct and still
/// necessary, just not sufficient on its own).
///
/// Results are cached against [AttributeStore.revision] plus the other
/// call inputs, so re-rendering after a selection-only change (no text
/// or formatting edit) is a cache hit.
class TextSpanRenderer implements DocumentRenderer<TextSpan> {
  RichTextRenderTheme theme;

  /// Called when the user taps a link span, with the link's URL.
  void Function(String url)? onTapLink;

  /// Called when the user taps a task-list checkbox glyph (`'[ ] '`/
  /// `'[x] '`), with the offset of that paragraph's start — enough for
  /// the host to look up and toggle that specific item. `null` (the
  /// default) means checkbox prefixes render but aren't tappable, same
  /// as [onTapLink] being unset for links.
  void Function(int paragraphStart)? onToggleCheckbox;

  /// Whether links should be interactive (clickable) in the rendered
  /// span. In an editable field, this should usually be `false` to
  /// allow cursor placement and selection on links; the host can
  /// still handle links via long-press (selection toolbar).
  bool interactiveLinks;

  TextSpanRenderer({
    this.theme = RichTextRenderTheme.standard,
    this.onTapLink,
    this.onToggleCheckbox,
    this.interactiveLinks = true,
  });

  TextSpan? _cachedSpan;
  String? _cachedText;
  int? _cachedRevision;
  int? _cachedParagraphRevision;
  TextStyle? _cachedStyle;
  TextRange? _cachedComposing;
  TextRange? _cachedMatchHighlight;
  TextRange? _cachedSelectionHighlight;
  RichTextRenderTheme? _cachedTheme;
  bool? _cachedInteractiveLinks;

  /// Tap recognizers attached to the current [_cachedSpan]'s link
  /// segments. `GestureRecognizer`s must be explicitly disposed —
  /// they're not garbage-collected safely on their own — so every
  /// rebuild disposes the previous batch before creating a new one, and
  /// [dispose] cleans up whatever's left when this renderer itself goes
  /// away (call it from the owning controller's `dispose()`).
  final List<TapGestureRecognizer> _recognizers = [];

  /// Renders with defaults — no base style, no composing region. Enough
  /// for a read-only preview; the live editor should call [renderSpan]
  /// directly so it can pass the current composing range.
  @override
  TextSpan render(EditorDocument document) => renderSpan(document);

  /// Renders `document` to a [TextSpan], applying `style` as the base,
  /// underlining `composingRange` (Android/iOS IME composition
  /// feedback), and painting `matchHighlightRange` (e.g. the current
  /// find-and-replace match) with [RichTextRenderTheme.matchHighlightColor].
  ///
  /// The match highlight is a distinct visual channel from Flutter's
  /// native [TextSelection] highlight on purpose: `EditableText` hides
  /// its selection highlight whenever the field loses focus (e.g. when
  /// a find bar's own text field takes focus), which would make "jump
  /// to next match" invisible the moment the find UI is interacted with.
  /// Baking the highlight into the rendered span itself means it stays
  /// visible regardless of which field has focus.
  TextSpan renderSpan(
      EditorDocument document, {
        TextStyle? style,
        TextRange? composingRange,
        TextRange? matchHighlightRange,
        TextRange? selectionHighlightRange,
      }) {
    final text = document.text;
    final revision = document.attributeStore.revision;
    // Header lives entirely in document.paragraphs now (ParagraphIndex),
    // not attributeStore — without also keying the cache on its own
    // revision counter, a header-only change (no text change, no
    // attributeStore change) would be invisible to this cache check,
    // and buildTextSpan would keep returning the stale, pre-header span
    // forever.
    final paragraphRevision = document.paragraphs.revision;

    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedRevision == revision &&
        _cachedParagraphRevision == paragraphRevision &&
        _cachedStyle == style &&
        _cachedComposing == composingRange &&
        _cachedMatchHighlight == matchHighlightRange &&
        _cachedSelectionHighlight == selectionHighlightRange &&
        _cachedTheme == theme &&
        _cachedInteractiveLinks == interactiveLinks) {
      return _cachedSpan!;
    }

    final span = _render(document, style, composingRange, matchHighlightRange, selectionHighlightRange);

    _cachedSpan = span;
    _cachedText = text;
    _cachedRevision = revision;
    _cachedParagraphRevision = paragraphRevision;
    _cachedStyle = style;
    _cachedComposing = composingRange;
    _cachedMatchHighlight = matchHighlightRange;
    _cachedSelectionHighlight = selectionHighlightRange;
    _cachedTheme = theme;
    _cachedInteractiveLinks = interactiveLinks;
    return span;
  }

  /// Invalidates the cache without changing anything else — call if
  /// `theme` was mutated in place rather than reassigned (mutating a
  /// `const`-ish theme object isn't possible here since it's
  /// `@immutable`, but this stays available for subclasses that add
  /// mutable state).
  void invalidateCache() => _cachedSpan = null;

  /// Disposes any tap recognizers still attached to the last rendered
  /// span. Call this when the renderer itself is being discarded (e.g.
  /// from `RichEditorController.dispose()`) — not between normal
  /// rebuilds, which already dispose the previous batch themselves.
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
    final recognizer = TapGestureRecognizer()..onTap = () => onTapLink?.call(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  TapGestureRecognizer? _checkboxRecognizerFor(int paragraphStart) {
    if (onToggleCheckbox == null) return null;
    final recognizer = TapGestureRecognizer()..onTap = () => onToggleCheckbox?.call(paragraphStart);
    _recognizers.add(recognizer);
    return recognizer;
  }

  TextSpan _render(
      EditorDocument document,
      TextStyle? style,
      TextRange? composingRange,
      TextRange? matchHighlightRange,
      TextRange? selectionHighlightRange,
      ) {
    // A cache miss means we're about to build a brand new span tree —
    // dispose whatever recognizers the previous one was holding before
    // creating their replacements, so tapping a link never fires a
    // recognizer whose span isn't on screen anymore.
    _disposeRecognizers();

    final text = document.text;
    if (text.isEmpty) return TextSpan(text: text, style: style);

    final length = text.length;
    final hasComposing =
        composingRange != null && composingRange.isValid && composingRange.end > composingRange.start;
    final hasMatchHighlight = matchHighlightRange != null &&
        matchHighlightRange.isValid &&
        matchHighlightRange.end > matchHighlightRange.start;
    final hasSelectionHighlight = selectionHighlightRange != null &&
        selectionHighlightRange.isValid &&
        selectionHighlightRange.end > selectionHighlightRange.start;

    final spans = document.attributes;
    final hasListPrefix = _containsListPrefix(document);
    if (spans.isEmpty &&
        !hasComposing &&
        !hasMatchHighlight &&
        !hasSelectionHighlight &&
        !hasListPrefix &&
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
    );
    if (events.isEmpty && !hasListPrefix) {
      return TextSpan(text: text, style: style);
    }

    return TextSpan(style: style, children: _buildChildren(document, events, style));
  }

  /// Whether any paragraph starts with a literal list prefix — used
  /// only to decide whether [_render] can take its plain-`TextSpan`
  /// fast path or needs the full event sweep to style that prefix.
  ///
  /// Iterates `document.paragraphs.records` — already computed, already
  /// O(paragraphs) to walk — checking each record's own start with the
  /// bounded [listPrefixLength]. O(paragraphs) total, strictly cheaper
  /// than the O(document length) `text`-rescanning this used to do
  /// (paragraphs ≤ characters, always). Deliberately not a *stored*
  /// `hasAnyList` field on `ParagraphIndex`: unlike `hasAnyHeader`
  /// (which just reads the already-reliable `headerLevel` field on each
  /// record), list-ness has no stored field to read — computing it
  /// would need `ParagraphIndex` to have text access it deliberately
  /// doesn't have, or a cached boolean with no way to stay correct
  /// after `applyInsertion`/`applyDeletion`, which don't receive text
  /// either. This gets the same complexity win without either problem.
  bool _containsListPrefix(EditorDocument document) {
    final text = document.text;
    for (final record in document.paragraphs.records) {
      if (listPrefixLength(text, record.start) > 0) return true;
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
      ) {
    final events = <_StyleEvent>[];

    for (final attr in spans) {
      final start = clampInt(attr.start, 0, length);
      final end = clampInt(attr.end, 0, length);
      if (end <= start) continue;
      events.add(_StyleEvent(offset: start, type: attr.type, isStart: true, value: attr.value));
      events.add(_StyleEvent(offset: end, type: attr.type, isStart: false, value: attr.value));
    }

    // Forces the sweep to stop at every paragraph start, even one with
    // no other attribute beginning or ending exactly there — see the
    // class doc comment for why this matters for header specifically.
    for (final record in document.paragraphs.records) {
      if (record.start > 0) {
        events.add(_StyleEvent(
          offset: record.start,
          type: null,
          isStart: true,
          markerKind: _MarkerKind.paragraphBoundary,
        ));
      }
    }

    if (composingRange != null) {
      final cs = clampInt(composingRange.start, 0, length);
      final ce = clampInt(composingRange.end, 0, length);
      if (ce > cs) {
        events.add(_StyleEvent(offset: cs, type: null, isStart: true, markerKind: _MarkerKind.composing));
        events.add(_StyleEvent(offset: ce, type: null, isStart: false, markerKind: _MarkerKind.composing));
      }
    }

    if (matchHighlightRange != null) {
      final ms = clampInt(matchHighlightRange.start, 0, length);
      final me = clampInt(matchHighlightRange.end, 0, length);
      if (me > ms) {
        events.add(_StyleEvent(offset: ms, type: null, isStart: true, markerKind: _MarkerKind.matchHighlight));
        events.add(_StyleEvent(offset: me, type: null, isStart: false, markerKind: _MarkerKind.matchHighlight));
      }
    }

    if (selectionHighlightRange != null) {
      final ss = clampInt(selectionHighlightRange.start, 0, length);
      final se = clampInt(selectionHighlightRange.end, 0, length);
      if (se > ss) {
        events.add(_StyleEvent(offset: ss, type: null, isStart: true, markerKind: _MarkerKind.selectionHighlight));
        events.add(_StyleEvent(offset: se, type: null, isStart: false, markerKind: _MarkerKind.selectionHighlight));
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

  List<TextSpan> _buildChildren(EditorDocument document, List<_StyleEvent> events, TextStyle? baseStyle) {
    final text = document.text;
    final children = <TextSpan>[];
    final activeValues = {for (final type in AttributeType.values) type: <Object?>[]};
    var activeComposing = 0;
    var activeMatchHighlight = 0;
    var activeSelectionHighlight = 0;

    var currentPos = 0;
    var eventIndex = 0;
    String? currentHeaderLevel;
    bool? currentChecked;

    while (currentPos < text.length) {
      while (eventIndex < events.length && events[eventIndex].offset <= currentPos) {
        final event = events[eventIndex];
        if (event.type == null) {
          final delta = event.isStart ? 1 : -1;
          if (event.markerKind == _MarkerKind.matchHighlight) {
            activeMatchHighlight += delta;
          } else if (event.markerKind == _MarkerKind.selectionHighlight) {
            activeSelectionHighlight += delta;
          } else if (event.markerKind == _MarkerKind.paragraphBoundary) {
            // No counter needed: the event exists solely to force the
            // outer while loop to break a segment at this offset, so
            // currentHeaderLevel re-queries correctly below.
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

      final nextPos =
      eventIndex < events.length ? clampInt(events[eventIndex].offset, 0, text.length) : text.length;

      if (nextPos > currentPos) {
        final isParagraphStart = currentPos == 0 || text.codeUnitAt(currentPos - 1) == 0x0A;
        if (isParagraphStart) {
          // Header now reads from ParagraphIndex, not an
          // AttributeType.header event in the sweep above —
          // activeValues[AttributeType.header] is simply unused for
          // styling. Correctness here depends on the paragraphBoundary
          // events above guaranteeing isParagraphStart is actually
          // checked at every paragraph, not just wherever some other
          // event happens to land.
          currentHeaderLevel = document.paragraphs.paragraphAt(currentPos)?.headerLevel;
        }
        final prefixLen = isParagraphStart ? listPrefixLength(text, currentPos) : 0;
        final prefixEnd = clampInt(currentPos + prefixLen, currentPos, nextPos);
        if (isParagraphStart) {
          currentChecked = prefixLen > 0 ? checkboxStateOfPrefix(text.substring(currentPos, prefixEnd)) : null;
        }

        final resolvedStyle = _resolveStyle(
          baseStyle,
          activeValues,
          currentHeaderLevel,
          activeComposing > 0,
          activeMatchHighlight > 0,
          activeSelectionHighlight > 0,
        );

        // The prefix run is styled but otherwise ordinary text — same
        // character count as what's in the document, just a different
        // TextStyle. No link recognizer on it: a link overlapping a
        // literal '- ' at a paragraph start is a nonsensical combination
        // not worth complicating this split for. A checkbox prefix does
        // get a recognizer, though — that's the whole point of it being
        // tappable.
        if (prefixEnd > currentPos) {
          children.add(TextSpan(
            text: text.substring(currentPos, prefixEnd),
            style: _listPrefixStyle(resolvedStyle),
            recognizer: currentChecked != null ? _checkboxRecognizerFor(currentPos) : null,
          ));
        }

        if (nextPos > prefixEnd) {
          final linkUrl = activeValues[AttributeType.link]!.isEmpty
              ? null
              : activeValues[AttributeType.link]!.last as String?;
          // A checked item's own content (not the checkbox glyph) gets a
          // line-through on top of whatever else is active, so a bold or
          // linked word inside a checked item still reads as struck.
          final contentStyle = currentChecked == true
              ? resolvedStyle.copyWith(
            decoration: TextDecoration.combine([
              if (resolvedStyle.decoration != null && resolvedStyle.decoration != TextDecoration.none)
                resolvedStyle.decoration!,
              TextDecoration.lineThrough,
            ]),
          )
              : resolvedStyle;
          children.add(TextSpan(
            text: text.substring(prefixEnd, nextPos),
            style: contentStyle,
            recognizer: _recognizerFor(linkUrl),
          ));
        }
      }
      currentPos = nextPos;
    }

    return children;
  }

  TextStyle _resolveStyle(
      TextStyle? baseStyle,
      Map<AttributeType, List<Object?>> active,
      String? headerLevel,
      bool isComposing,
      bool isCurrentMatch,
      bool isSelectionHighlight,
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
    FontWeight fontWeight =
    isActive(AttributeType.bold) ? FontWeight.bold : (baseStyle?.fontWeight ?? FontWeight.normal);

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

    return (baseStyle ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: theme.lineHeight / fontSize,
      fontStyle: isActive(AttributeType.italic)
          ? FontStyle.italic
          : (baseStyle?.fontStyle ?? FontStyle.normal),
      color: colorArgb != null
          ? Color(colorArgb)
          : (linkUrl != null ? theme.linkColor : baseStyle?.color),
      // The current search match and selection highlight take priority.
      backgroundColor: isCurrentMatch
          ? theme.matchHighlightColor
          : (isSelectionHighlight
          ? theme.linkColor.withValues(alpha: 0.3)
          : (isActive(AttributeType.highlight)
          ? theme.highlightColor
          : (isCode ? theme.codeBackgroundColor : baseStyle?.backgroundColor))),
      decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
      fontFamily: isCode ? theme.codeFontFamily : baseStyle?.fontFamily,
    );
  }

  /// Styling for a literal list-prefix run (`'- '`, `'3. '`, etc.) —
  /// takes the already-resolved style for that position (so inline
  /// formatting like bold still applies) and layers the theme's marker
  /// color and weight on top. Purely presentational: `segmentStyle`'s
  /// text is unchanged, this only picks a different [TextStyle] for it.
  TextStyle _listPrefixStyle(TextStyle segmentStyle) {
    return segmentStyle.copyWith(
      color: theme.listMarkerColor,
      fontWeight: FontWeight.w600,
    );
  }
}