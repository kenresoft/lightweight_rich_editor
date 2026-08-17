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

/// What kind of marker a `type == null` event represents — composing
/// events, match-highlight events, and selection-highlight events all use
/// `type == null` (none are [AttributeType]s), so they need their own
/// discriminator to be tracked as separate counters during the sweep.
///
/// Not to be confused with list markers (bullet/number prefixes), which
/// this renderer no longer generates — see the removal note below.
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
  final AttributeType?
  type; // null means this is a marker event — see markerKind
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
/// Horizontal rules follow the exact same discipline, one level up: a
/// paragraph whose *entire* text is three or more hyphens (see
/// [isHorizontalRuleLine]) is styled as a muted divider-like line
/// instead of plain body text. No stored flag, no rewriting of what was
/// typed — a real full-bleed line (spanning the field's actual pixel
/// width regardless of how much was typed) would need to track live
/// text layout, which is a different, much riskier feature than
/// styling literal text differently.
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
  /// Reassigning this (e.g. a dark-mode theme swap) clears
  /// [_quantizedLineHeightCache] — that cache is keyed by font
  /// size/weight/style alone, not by [theme], so a new theme with a
  /// different [RichTextRenderTheme.lineHeight] needs a clean slate
  /// rather than silently reusing heights quantized against the old
  /// line height.
  RichTextRenderTheme get theme => _theme;
  set theme(RichTextRenderTheme value) {
    if (_theme == value) return;
    _theme = value;
    _quantizedLineHeightCache.clear();
  }

  RichTextRenderTheme _theme;

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
  /// `allMatchesRanges`, if given, paints every other range in it with
  /// [RichTextRenderTheme.otherMatchesHighlightColor] — a paler variant,
  /// so the *current* match (`matchHighlightRange`) stays the one that
  /// visually stands out. For cache-friendliness, pass the *same list
  /// instance* across calls when the underlying match set hasn't
  /// changed — this is compared by reference (`identical`), not deep
  /// equality, the same contract [lineBottomOffsets] already follows for
  /// its own list output; `SearchIndex.matches` already returns a stable
  /// reference for exactly this reason.
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
    List<TextRange>? allMatchesRanges,
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
  /// `theme` was mutated in place rather than reassigned (mutating a
  /// `const`-ish theme object isn't possible here since it's
  /// `@immutable`, but this stays available for subclasses that add
  /// mutable state).
  void invalidateCache() => _cachedSpan = null;

  List<double>? _cachedLineBottoms;
  double? _cachedLineBottomsWidth;
  StrutStyle? _cachedLineBottomsStrut;
  String? _cachedLineBottomsText;
  int? _cachedLineBottomsRevision;
  int? _cachedLineBottomsParagraphRevision;
  TextStyle? _cachedLineBottomsBaseStyle;
  TextHeightBehavior? _cachedLineBottomsHeightBehavior;

  /// The bottom Y offset (document/unscrolled space) of every actually
  /// *rendered* line, accounting for wrapping and any per-paragraph
  /// font-size difference (headers) — what `RuledLinesPainter` aligns
  /// ruled lines against, instead of assuming a fixed gap between every
  /// line regardless of what's actually there.
  ///
  /// Built by laying out the exact same [TextSpan] this renderer already
  /// produces (via [renderSpan]) through a throwaway [TextPainter] with
  /// the same `maxWidth`/`strutStyle` the real `TextField` uses, then
  /// reading [TextPainter.computeLineMetrics] — the same layout engine
  /// the real field goes through, so this necessarily agrees with it,
  /// without this renderer needing to independently model Flutter's
  /// strut/line-height interaction itself.
  ///
  /// Cached the same way [renderSpan] is (by document/paragraph
  /// revision), plus `maxWidth`/`strutStyle`/`style`, which a line
  /// layout depends on that a plain, unwrapped [TextSpan] doesn't. A
  /// cache hit returns the *same list instance* as last time — callers
  /// (`RuledLinesPainter.shouldRepaint`) can and should compare by
  /// reference rather than deep-equality for cheap per-frame checks.
  List<double> lineBottomOffsets(
    EditorDocument document, {
    required double maxWidth,
    TextStyle? style,
    required StrutStyle strutStyle,
    TextHeightBehavior? textHeightBehavior,
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
        _cachedLineBottomsHeightBehavior == textHeightBehavior) {
      return _cachedLineBottoms!;
    }

    final span = renderSpan(document, style: style);
    final painter = TextPainter(
      text: span,
      strutStyle: strutStyle,
      textDirection: TextDirection.ltr,
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
    return bottoms;
  }

  /// The document-space (unscrolled) Y offset of `charOffset`'s glyph —
  /// what a caller scrolling the editor's viewport to bring a specific
  /// character position into view (e.g. `RichTextEditor`'s scroll-to-
  /// current-search-match behavior) needs. Same parallel-[TextPainter]
  /// technique [lineBottomOffsets] uses, so it necessarily agrees with
  /// where that character actually renders in the real `TextField` —
  /// pass the exact same `maxWidth`/`style`/`strutStyle`/
  /// `textHeightBehavior` that field uses.
  ///
  /// Not cached: called only when something like the current search
  /// match actually changes (a rare event relative to keystrokes/
  /// scrolling), not on every frame, so the cost of one extra layout
  /// pass here isn't worth the bookkeeping a cache would add.
  double offsetYFor(
    EditorDocument document,
    int charOffset, {
    required double maxWidth,
    TextStyle? style,
    required StrutStyle strutStyle,
    TextHeightBehavior? textHeightBehavior,
  }) {
    final span = renderSpan(document, style: style);
    final painter = TextPainter(
      text: span,
      strutStyle: strutStyle,
      textDirection: TextDirection.ltr,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: textHeightBehavior,
    )..layout(maxWidth: maxWidth <= 0 ? double.infinity : maxWidth);

    final clamped = clampInt(charOffset, 0, document.text.length);
    return painter.getOffsetForCaret(TextPosition(offset: clamped), Rect.zero).dy;
  }

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
    // A cache miss means we're about to build a brand new span tree —
    // dispose whatever recognizers the previous one was holding before
    // creating their replacements, so tapping a link never fires a
    // recognizer whose span isn't on screen anymore.
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

  /// Whether any paragraph is a horizontal-rule line — same rationale
  /// and shape as [_containsListPrefix]: only used to decide the
  /// plain-`TextSpan` fast path, not stored anywhere.
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
    // paragraph's *own* presentational state might actually need
    // re-evaluating there — see the class doc comment for why this has
    // to happen at every relevant paragraph boundary, not just wherever
    // some other event happens to land, or `currentHeaderLevel` (etc.)
    // could go un-refreshed for a whole paragraph.
    //
    // "Might need re-evaluating" deliberately isn't "every paragraph,
    // unconditionally" (the previous version here) — a boundary is only
    // useful when something the sweep tracks per-paragraph could
    // plausibly differ from what it already carried over from the
    // paragraph before: header level or horizontal-rule-ness changing,
    // or (unconditionally, regardless of the neighbor) this paragraph
    // having its own list/checkbox prefix, since prefix styling is
    // always specific to that one paragraph's own leading characters —
    // never something that can be "inherited" from a neighbor the way
    // header/hr state can. Skipping the rest is a real, measured
    // performance fix, not just a tidy-up: a large note is
    // overwhelmingly plain body paragraphs with none of this — forcing
    // a separate `TextSpan` child at every single one of them anyway,
    // even though the resolved style demonstrably wouldn't have
    // changed, was costing a full extra sweep stop (and object
    // allocation) per paragraph for no visual difference at all.
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

      final nextPos = eventIndex < events.length
          ? clampInt(events[eventIndex].offset, 0, text.length)
          : text.length;

      if (nextPos > currentPos) {
        final isParagraphStart =
            currentPos == 0 || text.codeUnitAt(currentPos - 1) == 0x0A;
        if (isParagraphStart) {
          // Header now reads from ParagraphIndex, not an
          // AttributeType.header event in the sweep above —
          // activeValues[AttributeType.header] is simply unused for
          // styling. Correctness here depends on the paragraphBoundary
          // events above guaranteeing isParagraphStart is actually
          // checked at every paragraph, not just wherever some other
          // event happens to land.
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

        // A horizontal-rule line has no "prefix + content" shape at all
        // — the whole run of hyphens *is* the marker, styled uniformly,
        // with nothing after it to split out. Handled as its own branch
        // rather than folded into the prefix logic below, which assumes
        // a marker followed by unrelated content.
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
        // character count as what's in the document, just a different
        // TextStyle. No link recognizer on it: a link overlapping a
        // literal '- ' at a paragraph start is a nonsensical combination
        // not worth complicating this split for. A checkbox prefix does
        // get a recognizer, though — that's the whole point of it being
        // tappable.
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
          // A checked item's own content (not the checkbox glyph) gets a
          // line-through on top of whatever else is active, so a bold or
          // linked word inside a checked item still reads as struck.
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

  /// Keyed by `'$fontSize|${fontWeight.value}|$isItalic'` — the inputs
  /// [_quantizedLineHeight] actually depends on.
  final Map<String, double> _quantizedLineHeightCache = {};

  /// The line-box height to target for text at `fontSize`/`fontWeight`/
  /// `isItalic`, rounded *up* to the nearest whole multiple of
  /// [RichTextRenderTheme.lineHeight] rather than forced to exactly one
  /// line regardless of font size.
  ///
  /// Forcing every line to exactly `theme.lineHeight` (the previous
  /// behavior here) keeps the ruled-line grid perfectly regular, but a
  /// header's font is often intrinsically taller than one row —
  /// squeezing it into a single row's height doesn't shrink the glyphs,
  /// it just crams them into a box too short for them, so they crowd
  /// against (or visually cross) the ruled lines immediately above and
  /// below instead of sitting centered. Rounding up to a whole number of
  /// rows instead — 2 rows for a header that needs more than 1 but no
  /// more than 2, etc. — keeps every ruled line still landing exactly on
  /// a multiple of `theme.lineHeight` from the top (so nothing below a
  /// header ever drifts), while giving the header's own glyphs a box
  /// that's actually tall enough for them, centered within it via
  /// [TextLeadingDistribution.even] (see where this is consumed in
  /// `RichTextEditor` and [lineBottomOffsets] — both need the *same*
  /// leading distribution as this height quantization assumes, or the
  /// two would disagree about where a line's glyphs actually sit within
  /// its box).
  ///
  /// "Rows needed" is measured once per distinct (fontSize, fontWeight,
  /// isItalic) combination — via a throwaway [TextPainter] with no
  /// height override, i.e. Flutter's own natural line metrics for that
  /// style — and cached, rather than guessed at or hand-tuned per header
  /// level: a host can freely reconfigure `h1FontSize`/`h2FontSize`/
  /// `lineHeight`, or a plain size change via `AttributeType.size` can
  /// produce any font size at all, and this stays correct for all of
  /// them without needing to know in advance which ones "count as a
  /// header."
  double _quantizedLineHeight(
    double fontSize,
    FontWeight fontWeight,
    bool isItalic,
  ) {
    final key = '$fontSize|${fontWeight.value}|$isItalic';
    final cached = _quantizedLineHeightCache[key];
    if (cached != null) return cached;

    // This runs on every styled segment of every render, including the
    // very first paint — a bad result here (or an uncaught exception)
    // doesn't just mis-size one header, it can take the whole document
    // down with it. `theme.lineHeight` (the previous, always-safe
    // behavior) is the fallback for anything that doesn't come back
    // looking like a real, finite, positive measurement — a probe glyph
    // missing from a given font, a `computeLineMetrics()` result this
    // hasn't been tested against, or any other real-Skia behavior a
    // widget test running against Flutter's test-only text backend
    // can't be trusted to have already exercised.
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
          text: 'Ág', // tall ascender + descender, a representative worst case for natural line height
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
      // The current search match and selection highlight take priority;
      // any *other* search match comes next — still visually distinct
      // from ordinary formatting even where a match happens to overlap
      // manually-highlighted or code-styled text.
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

  /// Styling for a horizontal-rule line (`'---'`, or any longer run of
  /// hyphens — see `isHorizontalRuleLine`). Shares `listMarkerColor`
  /// deliberately: both are muted, structural (non-content) marks, not
  /// prose, so the same "quiet gray" treatment reads consistently rather
  /// than introducing a second marker color for a very similar role. The
  /// added letter-spacing is purely cosmetic — it fans the literal
  /// hyphens out a bit so a short run reads more like a broken line than
  /// a dash, without changing the character count or width in a way
  /// that depends on layout.
  TextStyle _horizontalRuleStyle(TextStyle segmentStyle) {
    return segmentStyle.copyWith(
      color: theme.listMarkerColor,
      fontWeight: FontWeight.w300,
      letterSpacing: 3.0,
    );
  }
}
