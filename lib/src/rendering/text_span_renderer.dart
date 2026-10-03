import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/attribute_store.dart';
import '../core/editor_document.dart';
import '../models/attribute_type.dart';
import '../models/code_block.dart';
import '../models/image_block.dart';
import '../core/paragraph_record.dart';
import '../models/text_attribute.dart';
import '../utils/clamp_int.dart';
import '../utils/horizontal_rule.dart';
import '../utils/list_prefix.dart';
import 'code_block_region.dart';
import 'image_region.dart';
import 'code_highlighter.dart';
import 'document_renderer.dart';
import 'render_theme.dart';
import 'ruled_row_metrics.dart';

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
class _ColorRun {
  const _ColorRun(this.start, this.end, this.color);
  final int start;
  final int end;
  final Color color;
}

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
  /// Reassigning this (e.g. a dark-mode theme swap) drops every
  /// [RuledRowMetrics] instance, whose pitch and fit measurements were all
  /// taken against the old [RichTextRenderTheme.lineHeight]/`rowFill`.
  RichTextRenderTheme get theme => _theme;
  set theme(RichTextRenderTheme value) {
    if (_theme == value) return;
    _theme = value;
    _rowMetricsByFamily.clear();
    activeRowMetrics = null;
  }

  RichTextRenderTheme _theme;

  // One RuledRowMetrics per base font family for the current (theme,
  // scaler, dpr) — the real TextField's merged style and the editor's own
  // measurement style can differ in family, and both hit this on every
  // frame, so a single slot would thrash. Cleared whenever any of the
  // shared inputs changes, so stale measurements can never outlive them.
  final Map<String?, RuledRowMetrics> _rowMetricsByFamily = {};
  TextScaler? _rowMetricsScaler;
  double? _rowMetricsDpr;

  /// The row grid for the given effective scaler / pixel ratio / base style.
  ///
  /// The one place row geometry is decided: [renderSpan] (span heights),
  /// `RichTextEditor` (strut, fallback rule spacing, painter) and the
  /// toolbar's font-size limits all read it from here, so they cannot
  /// disagree about the pitch or which sizes fit.
  RuledRowMetrics rowMetrics({
    TextScaler textScaler = TextScaler.noScaling,
    double devicePixelRatio = 1.0,
    TextStyle? style,
  }) {
    if (_rowMetricsScaler != textScaler ||
        _rowMetricsDpr != devicePixelRatio) {
      _rowMetricsByFamily.clear();
      _rowMetricsScaler = textScaler;
      _rowMetricsDpr = devicePixelRatio;
    }
    final family = style?.fontFamily;
    return _rowMetricsByFamily[family] ??= RuledRowMetrics(
      theme: theme,
      textScaler: textScaler,
      devicePixelRatio: devicePixelRatio,
      baseFontFamily: family,
    );
  }

  /// The metrics of the most recent *real* render (recorded by the
  /// controller's `buildTextSpan`), which is what a toolbar should quote
  /// font-size limits from. `null` before the first build.
  RuledRowMetrics? activeRowMetrics;

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
  TextScaler? _cachedTextScaler;
  double? _cachedDevicePixelRatio;

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
    // Must match whatever the real `TextField` will apply (its own
    // ambient `MediaQuery.textScalerOf(context)`) -- header/oversized-run
    // clamping (see `_clampedFontSize`) measures glyphs at the *scaled*
    // size, so a mismatched scaler here would fit against the wrong
    // target and let real (scaled) glyphs overflow their row again.
    TextScaler textScaler = TextScaler.noScaling,
    // Rows are snapped to whole physical pixels, so this must match the
    // real view's ratio as well.
    double devicePixelRatio = 1.0,
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
        _cachedInteractiveLinks == interactiveLinks &&
        _cachedTextScaler == textScaler &&
        _cachedDevicePixelRatio == devicePixelRatio) {
      return _cachedSpan!;
    }

    final span = _render(
      document,
      style,
      composingRange,
      matchHighlightRange,
      selectionHighlightRange,
      allMatchesRanges,
      rowMetrics(
        textScaler: textScaler,
        devicePixelRatio: devicePixelRatio,
        style: style,
      ),
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
    _cachedTextScaler = textScaler;
    _cachedDevicePixelRatio = devicePixelRatio;
    return span;
  }

  /// Invalidates the cache without changing anything else — call if
  /// `theme` was mutated in place rather than reassigned.
  void invalidateCache() => _cachedSpan = null;

  List<double>? _cachedLineBottoms;
  List<CodeBlockRegion> _cachedCodeBlocks = const [];
  List<BlankLineRegion> _cachedBlankLines = const [];
  List<Rect> _cachedInlineCode = const [];
  List<ImageRegion> _cachedImages = const [];

  /// The image blocks of the document (cached with [codeBlocks]).
  List<ImageRegion> get imageBlocks => _cachedImages;

  /// Inline-code boxes (cached with [codeBlocks]).
  List<Rect> get inlineCodeRects => _cachedInlineCode;

  /// The code blocks of the document as of the last [lineBottomOffsets] call
  /// (cached under the same key, so it is as fresh as the bottoms it came with).
  List<CodeBlockRegion> get codeBlocks => _cachedCodeBlocks;

  /// The blank lines of the document (same cache as [codeBlocks]) that a
  /// selection of `[start, end)` selects the line break of — the ones a text
  /// field leaves unpainted. Sorted by offset.
  List<BlankLineRegion> blankLinesSelected(int start, int end) {
    final all = _cachedBlankLines;
    if (all.isEmpty || end <= start) return const [];
    var lo = 0;
    var hi = all.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (all[mid].offset < start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final out = <BlankLineRegion>[];
    for (var i = lo; i < all.length && all[i].offset < end; i++) {
      out.add(all[i]);
    }
    return out;
  }
  double? _cachedLineBottomsWidth;
  StrutStyle? _cachedLineBottomsStrut;
  String? _cachedLineBottomsText;
  int? _cachedLineBottomsRevision;
  int? _cachedLineBottomsParagraphRevision;
  TextStyle? _cachedLineBottomsBaseStyle;
  TextHeightBehavior? _cachedLineBottomsHeightBehavior;
  TextDirection? _cachedLineBottomsDirection;
  TextScaler? _cachedLineBottomsTextScaler;
  double? _cachedLineBottomsDpr;
  RichTextRenderTheme? _cachedLineBottomsTheme;

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
    // Same requirement as `renderSpan`'s: must match the real `TextField`'s
    // ambient scaler, or this measurement disagrees with what actually
    // renders.
    TextScaler textScaler = TextScaler.noScaling,
    double devicePixelRatio = 1.0,
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
        _cachedLineBottomsDirection == textDirection &&
        _cachedLineBottomsTextScaler == textScaler &&
        _cachedLineBottomsDpr == devicePixelRatio &&
        _cachedLineBottomsTheme == theme) {
      return _cachedLineBottoms!;
    }

    final span = renderSpan(
      document,
      style: style,
      textScaler: textScaler,
      devicePixelRatio: devicePixelRatio,
    );
    final painter = TextPainter(
      text: span,
      strutStyle: strutStyle,
      textDirection: textDirection,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: textHeightBehavior,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth <= 0 ? double.infinity : maxWidth);

    final bottoms = <double>[];
    final lines = painter.computeLineMetrics();
    final forced = strutStyle.forceStrutHeight == true &&
            strutStyle.fontSize != null &&
            strutStyle.height != null
        ? strutStyle.height! * textScaler.scale(strutStyle.fontSize!)
        : null;
    if (forced != null && forced > 0) {
      // A forced strut makes every visual line exactly that tall, whatever
      // fonts its runs resolve to. `LineMetrics.height` is NOT reliable here:
      // it reports each run font's own ascent+descent (measured 31px for a
      // Latin+CJK line whose real, laid-out box is 30px), so summing it would
      // put the rules out of step with the text the field actually paints.
      for (var i = 1; i <= lines.length; i++) {
        bottoms.add(i * forced);
      }
    } else {
      var y = 0.0;
      for (final line in lines) {
        y += line.height;
        bottoms.add(y);
      }
    }

    _cachedLineBottoms = bottoms;
    _cachedCodeBlocks = _codeRegions(document, painter, bottoms);
    _cachedInlineCode = _inlineCodeRects(document, painter);
    _cachedImages = _imageRegions(document, painter, bottoms);
    _cachedBlankLines = _blankLineRegions(document, painter, bottoms);
    _cachedLineBottomsText = text;
    _cachedLineBottomsRevision = revision;
    _cachedLineBottomsParagraphRevision = paragraphRevision;
    _cachedLineBottomsWidth = maxWidth;
    _cachedLineBottomsStrut = strutStyle;
    _cachedLineBottomsBaseStyle = style;
    _cachedLineBottomsHeightBehavior = textHeightBehavior;
    _cachedLineBottomsDirection = textDirection;
    _cachedLineBottomsTextScaler = textScaler;
    _cachedLineBottomsDpr = devicePixelRatio;
    _cachedLineBottomsTheme = theme;
    return bottoms;
  }

  // Inline `code` runs as one tight box per visual line (glyph height, not row
  // height), in the same coordinates as the text. The paper layer paints them as
  // rounded pills behind the text; a text background could only be a flat
  // full-row rectangle. Code inside a code-block paragraph is skipped (the block
  // is its own surface).
  List<Rect> _inlineCodeRects(EditorDocument document, TextPainter painter) {
    final out = <Rect>[];
    for (final span in document.attributes) {
      if (span.type != AttributeType.code || span.end <= span.start) continue;
      if (out.length >= 4000) break;
      final para = document.paragraphs.paragraphAt(span.start);
      if (para != null && isCodeBlockLevel(para.headerLevel)) continue;
      out.addAll([
        for (final box in painter.getBoxesForSelection(
          TextSelection(baseOffset: span.start, extentOffset: span.end),
          boxHeightStyle: ui.BoxHeightStyle.tight,
        ))
          if (box.right > box.left) box.toRect(),
      ]);
    }
    return out;
  }

  // Every empty paragraph that has a line break of its own (so not the last
  // paragraph), with its row. Only blank lines are queried, so this stays cheap
  // however long the document is.
  List<BlankLineRegion> _blankLineRegions(EditorDocument document, TextPainter painter, List<double> bottoms) {
    if (bottoms.isEmpty) return const [];
    final records = document.paragraphs.records;
    final out = <BlankLineRegion>[];
    for (var i = 0; i < records.length - 1; i++) {
      final r = records[i];
      if (r.start != r.end || isImageLevel(r.headerLevel)) continue;
      final dy = painter.getOffsetForCaret(TextPosition(offset: r.start), Rect.zero).dy;
      var lo = 0;
      var hi = bottoms.length - 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (bottoms[mid] > dy + 0.5) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      out.add(BlankLineRegion(offset: r.start, top: lo == 0 ? 0.0 : bottoms[lo - 1], bottom: bottoms[lo]));
    }
    return out;
  }

  // Each run of image rows -> its Y extent. Only documents that contain an image
  // pay for this. A level that appears in two separate runs (a block broken in
  // two by an edit) is drawn once, from its first run.
  List<ImageRegion> _imageRegions(EditorDocument document, TextPainter painter, List<double> bottoms) {
    if (bottoms.isEmpty || !document.paragraphs.hasAnyImage) return const [];
    final out = <ImageRegion>[];
    final seen = <String>{};

    double topOf(int offset) {
      final dy = painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
      var lo = 0;
      var hi = bottoms.length - 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (bottoms[mid] > dy + 0.5) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      return lo == 0 ? 0.0 : bottoms[lo - 1];
    }

    double bottomOf(int offset) {
      final dy = painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
      var lo = 0;
      var hi = bottoms.length - 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (bottoms[mid] > dy + 0.5) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      return bottoms[lo];
    }

    void emit(ParagraphRecord first, ParagraphRecord last, int rows) {
      final level = first.headerLevel!;
      final id = imageIdOf(level);
      if (id == null || !seen.add(level)) return;
      out.add(ImageRegion(
        top: topOf(first.start),
        bottom: bottomOf(last.start),
        start: first.start,
        end: last.end,
        id: id,
        level: level,
        rows: rows,
      ));
    }

    ParagraphRecord? first;
    ParagraphRecord? last;
    var rows = 0;
    for (final r in document.paragraphs.records) {
      if (!isImageLevel(r.headerLevel)) {
        if (first != null) emit(first, last!, rows);
        first = null;
        continue;
      }
      if (first != null && first.headerLevel != r.headerLevel) {
        emit(first, last!, rows);
        first = null;
      }
      if (first == null) rows = 0;
      first ??= r;
      last = r;
      rows++;
    }
    if (first != null) emit(first, last!, rows);
    return out;
  }

  // Each run of consecutive code lines of one language -> its Y extent, from
  // the same laid-out paragraph the line bottoms came from.
  List<CodeBlockRegion> _codeRegions(EditorDocument document, TextPainter painter, List<double> bottoms) {
    if (bottoms.isEmpty || !document.paragraphs.hasAnyCodeBlock) return const [];
    final regions = <CodeBlockRegion>[];
    int lineIndexAt(int offset) {
      final dy = painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
      var lo = 0;
      var hi = bottoms.length - 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (bottoms[mid] > dy + 0.5) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      return lo;
    }

    // Right edge of the visual line containing [offset]; 0 for an empty line.
    double lineRight(int offset) {
      final range = painter.getLineBoundary(TextPosition(offset: offset));
      if (range.isCollapsed) return 0.0;
      var right = 0.0;
      for (final box in painter.getBoxesForSelection(TextSelection(baseOffset: range.start, extentOffset: range.end))) {
        if (box.right > right) right = box.right;
      }
      return right;
    }

    String? guessed(ParagraphRecord first, ParagraphRecord last) {
      if (codeBlockLanguage(first.headerLevel) != null) return null;
      final g = _guessedLanguage(document.text.substring(first.start, last.end));
      return canHighlight(g) ? g : null;
    }

    void emit(ParagraphRecord first, ParagraphRecord last) {
      final a = lineIndexAt(first.start);
      final b = lineIndexAt(last.end);
      regions.add(CodeBlockRegion(
        top: a == 0 ? 0.0 : bottoms[a - 1],
        bottom: bottoms[b],
        start: first.start,
        end: last.end,
        language: codeBlockLanguage(first.headerLevel),
        guessedLanguage: guessed(first, last),
        firstLineRight: lineRight(first.start),
        previousLineRight: first.start == 0 ? 0.0 : lineRight(first.start - 1),
        firstRowBottom: bottoms[a],
        lastRowTop: b == 0 ? 0.0 : bottoms[b - 1],
        lastLineRight: lineRight(last.end),
      ));
    }

    ParagraphRecord? first;
    ParagraphRecord? last;
    for (final r in document.paragraphs.records) {
      if (!isCodeBlockLevel(r.headerLevel)) {
        if (first != null) emit(first, last!);
        first = null;
        continue;
      }
      if (first != null && first.headerLevel != r.headerLevel) {
        emit(first, last!);
        first = null;
      }
      first ??= r;
      last = r;
    }
    if (first != null) emit(first, last!);
    return regions;
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
    TextScaler textScaler = TextScaler.noScaling,
    double devicePixelRatio = 1.0,
  }) {
    final span = renderSpan(
      document,
      style: style,
      textScaler: textScaler,
      devicePixelRatio: devicePixelRatio,
    );
    final painter = TextPainter(
      text: span,
      strutStyle: strutStyle,
      textDirection: textDirection,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: textHeightBehavior,
      textScaler: textScaler,
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
    RuledRowMetrics metrics,
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
      children: _buildChildren(document, events, style, metrics),
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
      final hasOwnPrefix = !isHr && !isCodeBlockLevel(record.headerLevel) && listPrefixLength(text, record.start) > 0;
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
    RuledRowMetrics metrics,
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
    var currentIsCode = false;
    final codeRuns = _codeColorRuns(document);
    var runCursor = 0;

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
          currentIsCode = isCodeBlockLevel(currentHeaderLevel);
          currentIsHorizontalRule =
              record != null &&
              !currentIsCode &&
              isHorizontalRuleLine(text, record.start, record.end);
        }
        final prefixLen = isParagraphStart && !currentIsHorizontalRule && !currentIsCode
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
          metrics,
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
              text: _displayPrefix(text.substring(currentPos, prefixEnd), currentChecked),
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
          if (currentIsCode && codeRuns.isNotEmpty) {
            // Syntax colours: the same text split into runs, each differing from
            // the code style only in colour.
            var p = prefixEnd;
            while (runCursor < codeRuns.length && codeRuns[runCursor].end <= p) {
              runCursor++;
            }
            var k = runCursor;
            while (p < nextPos) {
              while (k < codeRuns.length && codeRuns[k].end <= p) {
                k++;
              }
              if (k < codeRuns.length && codeRuns[k].start < nextPos) {
                final run = codeRuns[k];
                if (run.start > p) {
                  children.add(TextSpan(text: text.substring(p, run.start), style: contentStyle));
                  p = run.start;
                }
                final e = run.end < nextPos ? run.end : nextPos;
                children.add(TextSpan(text: text.substring(p, e), style: contentStyle.copyWith(color: run.color)));
                p = e;
              } else {
                children.add(TextSpan(text: text.substring(p, nextPos), style: contentStyle));
                p = nextPos;
              }
            }
            runCursor = k;
          } else {
            children.add(
              TextSpan(
                text: text.substring(prefixEnd, nextPos),
                style: contentStyle,
                recognizer: _recognizerFor(linkUrl),
              ),
            );
          }
        }
      }
      currentPos = nextPos;
    }

    return children;
  }

  // Tokenisation is cached per (language, block text), so editing prose or a
  // different block does not re-scan a code block that did not change.
  final Map<String, List<CodeToken>> _tokenCache = {};

  final Map<String, String?> _guessCache = {};

  String? _guessedLanguage(String code) {
    if (_guessCache.containsKey(code)) return _guessCache[code];
    final guess = guessLanguage(code);
    if (_guessCache.length >= 24) _guessCache.remove(_guessCache.keys.first);
    return _guessCache[code] = guess;
  }

  List<CodeToken> _tokensFor(String language, String code) {
    final key = '$language\u0000$code';
    final hit = _tokenCache[key];
    if (hit != null) return hit;
    final tokens = tokenizeCode(code, language);
    if (_tokenCache.length >= 24) _tokenCache.remove(_tokenCache.keys.first);
    return _tokenCache[key] = tokens;
  }

  // Colour runs (document offsets, sorted) of every highlightable code block.
  List<_ColorRun> _codeColorRuns(EditorDocument document) {
    if (!document.paragraphs.hasAnyCodeBlock) return const [];
    final text = document.text;
    final runs = <_ColorRun>[];
    void block(ParagraphRecord first, ParagraphRecord last) {
      final code = text.substring(first.start, last.end);
      // A very long block stays plain: colouring it makes thousands of spans, which a
      // phone takes seconds to lay out, and the block is still boxed and monospaced.
      if (code.length > maxHighlightedCodeLength) return;
      // A labelled block uses its label; an unlabelled one is coloured by a
      // best-effort guess (never stored), or stays plain when unclear.
      final language = codeBlockLanguage(first.headerLevel) ?? _guessedLanguage(code);
      if (!canHighlight(language)) return;
      for (final t in _tokensFor(language!, code)) {
        runs.add(_ColorRun(first.start + t.start, first.start + t.end, theme.codeSyntax.colorOf(t.kind)));
      }
    }

    ParagraphRecord? first;
    ParagraphRecord? last;
    for (final r in document.paragraphs.records) {
      if (!isCodeBlockLevel(r.headerLevel)) {
        if (first != null) block(first, last!);
        first = null;
        continue;
      }
      if (first != null && first.headerLevel != r.headerLevel) {
        block(first, last!);
        first = null;
      }
      first ??= r;
      last = r;
    }
    if (first != null) block(first, last!);
    return runs;
  }

  TextStyle _resolveStyle(
    TextStyle? baseStyle,
    Map<AttributeType, List<Object?>> active,
    String? headerLevel,
    bool isComposing,
    bool isCurrentMatch,
    bool isSelectionHighlight,
    bool isOtherMatch,
    RuledRowMetrics metrics,
  ) {
    bool isActive(AttributeType type) => active[type]!.isNotEmpty;
    Object? topValue(AttributeType type) {
      final stack = active[type]!;
      return stack.isEmpty ? null : stack.last;
    }

    if (isCodeBlockLevel(headerLevel)) {
      return _codeBlockStyle(
        baseStyle,
        metrics,
        isCurrentMatch,
        isSelectionHighlight,
        isOtherMatch,
      );
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
    } else if (headerLevel == 'h3') {
      fontSize = theme.h3FontSize;
      fontWeight = FontWeight.bold;
    } else if (sizeValue != null) {
      fontSize = sizeValue.toDouble();
    }
    final isHeader = headerLevel == 'h1' || headerLevel == 'h2' || headerLevel == 'h3';

    final decorations = <TextDecoration>[
      if (isActive(AttributeType.underline) || isComposing || linkUrl != null)
        TextDecoration.underline,
      if (isActive(AttributeType.strikethrough)) TextDecoration.lineThrough,
    ];

    final isCode = isActive(AttributeType.code);
    final isItalic = isActive(AttributeType.italic);

    // Row policy (see RuledRowMetrics): a paragraph header is never shrunk —
    // it takes the minimum whole number of rows its measured glyph height
    // needs, and its line box is exactly that many pitches. Inline text is
    // fitted to one row instead, so no inline span can grow a row.
    final double resolvedFontSize;
    final int rows;
    if (isHeader) {
      resolvedFontSize = fontSize;
      rows = metrics.rowsForParagraph(fontSize, fontWeight);
    } else {
      resolvedFontSize = metrics.fitInlineFontSize(
        fontSize,
        fontWeight,
        isItalic,
        family: isCode ? theme.codeFontFamily : baseStyle?.fontFamily,
      );
      rows = 1;
    }

    return (baseStyle ?? const TextStyle()).copyWith(
      fontSize: resolvedFontSize,
      fontWeight: fontWeight,
      height: metrics.heightMultiplier(resolvedFontSize, rows: rows),
      // Spare leading goes above the glyphs, so the baseline keeps one
      // constant distance from the rule at every size (measured: even
      // distribution drifts by several px across sizes).
      leadingDistribution: TextLeadingDistribution.proportional,
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
                            // Inline code is a rounded pill painted by the paper
                            // layer (see inlineCodeRects), not a flat text background.
                            : baseStyle?.backgroundColor))),
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      // A link's underline is a quiet hairline in the link colour, so the
      // coloured text carries the link and the line only supports it.
      decorationColor: linkUrl != null && colorArgb == null && !isActive(AttributeType.underline)
          ? theme.linkColor.withValues(alpha: 0.45)
          : null,
      decorationThickness: linkUrl != null && !isActive(AttributeType.underline) ? 1.0 : null,
      fontFamily: isCode ? theme.codeFontFamily : baseStyle?.fontFamily,
    );
  }

  // A code line: monospace, one row, uniform — inline formatting stored on the
  // text is preserved in the document but not rendered inside a code block.
  // The size is fitted like any inline run, in the code family, so a fallback
  // glyph can not escape the row.
  TextStyle _codeBlockStyle(
    TextStyle? baseStyle,
    RuledRowMetrics metrics,
    bool isCurrentMatch,
    bool isSelectionHighlight,
    bool isOtherMatch,
  ) {
    final size = metrics.fitInlineFontSize(
      theme.baseFontSize * 0.92,
      FontWeight.normal,
      false,
      family: theme.codeFontFamily,
    );
    return (baseStyle ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      height: metrics.heightMultiplier(size),
      leadingDistribution: TextLeadingDistribution.proportional,
      fontFamily: theme.codeFontFamily,
      decoration: TextDecoration.none,
      backgroundColor: isCurrentMatch
          ? theme.matchHighlightColor
          : (isSelectionHighlight
                ? theme.linkColor.withValues(alpha: 0.3)
                : (isOtherMatch ? theme.otherMatchesHighlightColor : null)),
    );
  }

  static final RegExp _taskPrefix = RegExp(r'^([ \t]*)[-*+] \[[ xX]\] $');

  // A bullet item's '-' / '*' / '+' is drawn as a bullet dot. One character
  // for one character, so every offset in the document and the field still
  // lines up; the stored text is untouched (copy, export and undo see '- ').
  String _displayPrefix(String prefix, bool? checked) {
    if (checked != null) {
      // A task item's '- [ ] ' / '- [x] ' is drawn as a checkbox glyph, padded with
      // thin spaces so it is still exactly as many characters as the marker.
      final m = _taskPrefix.firstMatch(prefix);
      if (m == null) return prefix;
      final lead = m.group(1)!;
      // Two neighbours from the same symbol block, so they are drawn by the same plain
      // font and match. (The ballot box with check, U+2611, is an emoji on Android and
      // came out as a coloured tick next to a thin empty box.)
      final glyph = checked ? '☒' : '☐';
      // Hair spaces (about a tenth of an em each) keep the item's text starting about
      // where a bullet's or a number's does, instead of two ems in.
      return '$lead$glyph${' ' * (prefix.length - lead.length - 1)}';
    }
    final i = prefix.length - 2;
    if (i < 0 || prefix.codeUnitAt(prefix.length - 1) != 0x20) return prefix;
    final marker = prefix[i];
    if ((marker != '-' && marker != '*' && marker != '+') || prefix.substring(0, i).trim().isNotEmpty) return prefix;
    return '${prefix.substring(0, i)}• ';
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
