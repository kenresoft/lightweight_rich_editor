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
enum _MarkerKind { composing, matchHighlight, selectionHighlight }

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
/// Results are cached against [AttributeStore.revision] plus the other
/// call inputs, so re-rendering after a selection-only change (no text
/// or formatting edit) is a cache hit.
class TextSpanRenderer implements DocumentRenderer<TextSpan> {
  RichTextRenderTheme theme;

  /// Called when the user taps a link span, with the link's URL.
  void Function(String url)? onTapLink;

  /// Whether links should be interactive (clickable) in the rendered
  /// span. In an editable field, this should usually be `false` to
  /// allow cursor placement and selection on links; the host can
  /// still handle links via long-press (selection toolbar).
  bool interactiveLinks;

  TextSpanRenderer({
    this.theme = RichTextRenderTheme.standard,
    this.onTapLink,
    this.interactiveLinks = true,
  });

  TextSpan? _cachedSpan;
  String? _cachedText;
  int? _cachedRevision;
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

    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedRevision == revision &&
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
    final hasListPrefix = _containsListPrefix(text);
    if (spans.isEmpty &&
        !hasComposing &&
        !hasMatchHighlight &&
        !hasSelectionHighlight &&
        !hasListPrefix) {
      return TextSpan(text: text, style: style);
    }

    final events = _buildEvents(
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

  /// Whether any paragraph in `text` starts with a literal list prefix
  /// — used only to decide whether [_render] can take its plain-`TextSpan`
  /// fast path or needs the full event sweep to style that prefix.
  ///
  /// One pass over `text`: `pos` only ever advances to `next + 1`, so
  /// the repeated `text.indexOf('\n', pos)` calls together cover each
  /// character once, not once per paragraph — O(document length) total,
  /// same order as building the plain-text span itself. This is
  /// deliberately *not* the per-newline pattern the old list-attribute
  /// code used (see the removal notes on `AttributeType`): there's no
  /// nested O(document length) call — like `_paragraphBounds` used to
  /// be — inside this loop.
  bool _containsListPrefix(String text) {
    var pos = 0;
    while (pos <= text.length) {
      if (listPrefixLength(text, pos) > 0) return true;
      final next = text.indexOf('\n', pos);
      if (next == -1) break;
      pos = next + 1;
    }
    return false;
  }

  List<_StyleEvent> _buildEvents(
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

    while (currentPos < text.length) {
      while (eventIndex < events.length && events[eventIndex].offset <= currentPos) {
        final event = events[eventIndex];
        if (event.type == null) {
          final delta = event.isStart ? 1 : -1;
          if (event.markerKind == _MarkerKind.matchHighlight) {
            activeMatchHighlight += delta;
          } else if (event.markerKind == _MarkerKind.selectionHighlight) {
            activeSelectionHighlight += delta;
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
        final prefixLen = isParagraphStart ? listPrefixLength(text, currentPos) : 0;
        final prefixEnd = clampInt(currentPos + prefixLen, currentPos, nextPos);

        final resolvedStyle = _resolveStyle(
          baseStyle,
          activeValues,
          activeComposing > 0,
          activeMatchHighlight > 0,
          activeSelectionHighlight > 0,
        );

        // The prefix run is styled but otherwise ordinary text — same
        // character count as what's in the document, just a different
        // TextStyle. No recognizer on it: a link overlapping a literal
        // '- ' at a paragraph start is a nonsensical combination not
        // worth complicating this split for.
        if (prefixEnd > currentPos) {
          children.add(TextSpan(
            text: text.substring(currentPos, prefixEnd),
            style: _listPrefixStyle(resolvedStyle),
          ));
        }

        if (nextPos > prefixEnd) {
          final linkUrl = activeValues[AttributeType.link]!.isEmpty
              ? null
              : activeValues[AttributeType.link]!.last as String?;
          children.add(TextSpan(
            text: text.substring(prefixEnd, nextPos),
            style: resolvedStyle,
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
      bool isComposing,
      bool isCurrentMatch,
      bool isSelectionHighlight,
      ) {
    bool isActive(AttributeType type) => active[type]!.isNotEmpty;
    Object? topValue(AttributeType type) {
      final stack = active[type]!;
      return stack.isEmpty ? null : stack.last;
    }

    final headerLevel = topValue(AttributeType.header) as String?;
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