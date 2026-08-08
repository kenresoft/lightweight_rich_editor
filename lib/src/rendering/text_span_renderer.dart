import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/attribute_store.dart';
import '../core/editor_document.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/clamp_int.dart';
import 'document_renderer.dart';
import 'render_theme.dart';

/// What kind of marker a `type == null` event represents — composing
/// events and match-highlight events both use `type == null` (neither
/// is an [AttributeType]), so they need their own discriminator to be
/// tracked as separate counters during the sweep.
enum _MarkerKind { composing, matchHighlight }

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
  RichTextRenderTheme? _cachedTheme;

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
      }) {
    final text = document.text;
    final revision = document.attributeStore.revision;

    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedRevision == revision &&
        _cachedStyle == style &&
        _cachedComposing == composingRange &&
        _cachedMatchHighlight == matchHighlightRange &&
        _cachedTheme == theme &&
        _cachedInteractiveLinks == interactiveLinks) {
      return _cachedSpan!;
    }

    final span = _render(document, style, composingRange, matchHighlightRange);

    _cachedSpan = span;
    _cachedText = text;
    _cachedRevision = revision;
    _cachedStyle = style;
    _cachedComposing = composingRange;
    _cachedMatchHighlight = matchHighlightRange;
    _cachedTheme = theme;
    _cachedInteractiveLinks = interactiveLinks;
    return span;
  }

  bool? _cachedInteractiveLinks;

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

    final spans = document.attributes;
    if (spans.isEmpty && !hasComposing && !hasMatchHighlight) {
      return TextSpan(text: text, style: style);
    }

    final events = _buildEvents(
      spans,
      length,
      hasComposing ? composingRange : null,
      hasMatchHighlight ? matchHighlightRange : null,
    );
    if (events.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    return TextSpan(style: style, children: _buildChildren(text, events, style));
  }

  List<_StyleEvent> _buildEvents(
      List<TextAttribute> spans,
      int length,
      TextRange? composingRange,
      TextRange? matchHighlightRange,
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

    events.sort((a, b) {
      final cmp = a.offset.compareTo(b.offset);
      // Process ends before starts at the same offset, so a span that
      // ends exactly where the next begins doesn't momentarily double up.
      return cmp != 0 ? cmp : (a.isStart ? 1 : 0) - (b.isStart ? 1 : 0);
    });

    return events;
  }

  List<TextSpan> _buildChildren(String text, List<_StyleEvent> events, TextStyle? baseStyle) {
    final children = <TextSpan>[];
    final activeValues = {for (final type in AttributeType.values) type: <Object?>[]};
    var activeComposing = 0;
    var activeMatchHighlight = 0;

    var currentPos = 0;
    var eventIndex = 0;

    while (currentPos < text.length) {
      while (eventIndex < events.length && events[eventIndex].offset <= currentPos) {
        final event = events[eventIndex];
        if (event.type == null) {
          final delta = event.isStart ? 1 : -1;
          if (event.markerKind == _MarkerKind.matchHighlight) {
            activeMatchHighlight += delta;
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
        final linkUrl = activeValues[AttributeType.link]!.isEmpty
            ? null
            : activeValues[AttributeType.link]!.last as String?;
        children.add(TextSpan(
          text: text.substring(currentPos, nextPos),
          style: _resolveStyle(baseStyle, activeValues, activeComposing > 0, activeMatchHighlight > 0),
          recognizer: _recognizerFor(linkUrl),
        ));
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
      // The current search match takes priority over any other
      // background (including the `highlight` attribute) — it needs to
      // stand out distinctly, and it's the thing the user just asked to
      // see, so it shouldn't blend into or hide behind existing styling.
      backgroundColor: isCurrentMatch
          ? theme.matchHighlightColor
          : (isActive(AttributeType.highlight)
          ? theme.highlightColor
          : (isCode ? theme.codeBackgroundColor : baseStyle?.backgroundColor)),
      decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
      fontFamily: isCode ? theme.codeFontFamily : baseStyle?.fontFamily,
    );
  }
}