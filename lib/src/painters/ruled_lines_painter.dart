import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../images/rich_image_cache.dart';
import '../models/image_block.dart' show pendingImageId;
import '../rendering/code_block_region.dart';
import '../rendering/image_region.dart';

/// The style of ruled lines to draw in the background.
enum RuledLineStyle {
  /// No lines are drawn.
  none,

  /// Solid lines are drawn.
  solid,

  /// Dashed lines are drawn.
  dashed,
}

/// A custom painter that draws notebook-style ruled lines and a margin line.
///
/// Ruled lines are drawn at [lineBottoms] — the real bottom edge of every
/// actually-rendered line of text (see `TextSpanRenderer.lineBottomOffsets`),
/// not a fixed-interval guess, so they stay aligned even when a line
/// wraps or a header's larger font makes one line taller than the rest.
///
/// Once [lineBottoms] runs out, lines continue at the constant
/// [fallbackLineHeight] — the blank "rest of the page" look.
class RuledLinesPainter extends CustomPainter {
  /// Creates a [RuledLinesPainter].
  RuledLinesPainter({
    required this.lineBottoms,
    required this.fallbackLineHeight,
    required this.topPadding,
    required this.scrollOffset,
    required this.marginOpacity,
    required this.lineStyle,
    required this.marginLineX,
    this.devicePixelRatio = 1.0,
    this.codeBlocks = const [],
    this.codeBlockColor = const Color(0x1F78909C),
    this.codeLeft = 0.0,
    this.codeRight = 0.0,
    this.codeBorderColor = const Color(0x2978909C),
    this.inlineCode = const [],
    this.inlineCodeLeft = 0.0,
    this.inlineCodeColor = const Color(0x1F78909C),
    this.imageBlocks = const [],
    this.imageCache,
    this.imageLeft = 0.0,
    this.imageRight = 0.0,
    this.selectionStart = -1,
    this.selectionEnd = -1,
    this.imageAccent = const Color(0xFF3F51B5),
    this.pageIsDark = false,
    this.selectedBlankLines = const [],
    this.selectionColor = const Color(0x663F51B5),
    this.selectionBarLeft = 0.0,
    this.selectionBarWidth = 0.0,
    this.lineColor = const Color(0x66607D8B),
    this.marginColor = const Color(0xCCFFCDD2),
  }) : super(repaint: imageCache) {
    _linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineStyle == RuledLineStyle.dashed ? 0.7 : 1.0
      ..isAntiAlias = false;

    _marginPaint = Paint()
      ..color = marginColor.withValues(alpha: marginColor.a * marginOpacity)
      ..strokeWidth = 2.0
      ..isAntiAlias = true;
  }

  /// The bottom Y offset (document/unscrolled space, relative to
  /// [topPadding]) of every actually-rendered line — see
  /// `TextSpanRenderer.lineBottomOffsets`. Sorted ascending by
  /// construction, which is what makes the binary search in
  /// [_firstVisibleIndex] valid.
  final List<double> lineBottoms;

  /// The notebook's row pitch (`RuledRowMetrics.pitch`, already text-scaled).
  ///
  /// Continued below the last entry in [lineBottoms] for the blank ruled
  /// space past the document's content, and used to draw the interior rules
  /// of a line that spans several rows (a heading): each measured line
  /// contributes one rule per whole pitch it is tall.
  final double fallbackLineHeight;

  /// Physical pixels per logical pixel; rule positions are snapped to it so
  /// un-antialiased 1px lines never land unevenly between rows.
  final double devicePixelRatio;

  /// Code blocks to paint a rounded background for (document coordinates), and
  /// the horizontal extent to paint it over. Ruled lines inside a block are
  /// not drawn, so paper rules never run through code.
  final List<CodeBlockRegion> codeBlocks;
  final Color codeBlockColor;
  final double codeLeft;
  final double codeRight;
  final Color codeBorderColor;

  /// Inline-code boxes (text-area relative, see `TextSpanRenderer.inlineCodeRects`),
  /// painted as rounded pills; [inlineCodeLeft] is the text area's left padding.
  final List<Rect> inlineCode;
  final double inlineCodeLeft;
  final Color inlineCodeColor;

  /// Image blocks to paint (document coordinates) and the decoded pictures to
  /// paint them from; [imageLeft]/[imageRight] is the horizontal extent a
  /// picture may use. A block the cache has not decoded yet shows a quiet
  /// placeholder. The selection touching a block outlines it in [imageAccent].
  final List<ImageRegion> imageBlocks;
  final RichImageCache? imageCache;
  final double imageLeft;
  final double imageRight;
  final int selectionStart;
  final int selectionEnd;
  final Color imageAccent;

  /// Whether the page is dark, so a see-through picture that would vanish on it (a black
  /// logo) is shown on a light card, and a white one on a light page on a dark card.
  final bool pageIsDark;

  /// Vertical air between a picture and the rows above and below it.
  static const double imageInset = 4.0;

  /// Where a picture of [imageSize] is drawn in [area]: as large as fits
  /// (never distorted), against the top-left corner, so a block that is a little
  /// taller than its picture leaves the spare room below it, not above.
  static Rect imageDestination(Rect area, Size imageSize) {
    if (imageSize.isEmpty || area.isEmpty) return area;
    final fitted = applyBoxFit(BoxFit.contain, imageSize, area.size).destination;
    return Alignment.topLeft.inscribe(fitted, area);
  }

  /// Blank lines a selection runs across, marked with a short bar in
  /// [selectionColor] at [selectionBarLeft] (the field paints nothing for a
  /// selected line break that has no glyphs).
  final List<BlankLineRegion> selectedBlankLines;
  final Color selectionColor;
  final double selectionBarLeft;
  final double selectionBarWidth;

  /// The top padding of the text area.
  final double topPadding;

  /// The current scroll offset.
  final double scrollOffset;

  /// The opacity of the margin line (used for animation).
  final double marginOpacity;

  /// The style of ruled lines.
  final RuledLineStyle lineStyle;

  /// The X coordinate of the vertical margin line.
  final double marginLineX;

  /// The color of the horizontal ruled lines.
  final Color lineColor;

  /// The color of the vertical margin line.
  final Color marginColor;

  late final Paint _linePaint;
  late final Paint _marginPaint;

  @override
  void paint(Canvas canvas, Size size) {
    // Blocks and selection bars scroll with the text, so they are cut at the
    // text area's top edge like the text itself: with a header above the
    // editor (a title, chips) they must not bleed up behind it.
    // Paper rules run under the cards (the cards are translucent), so a block
    // sits on the page like a slip laid over it instead of cutting the ruling.
    if (lineStyle != RuledLineStyle.none) {
      _drawRuledLines(canvas, size);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, topPadding, size.width, size.height));
    _drawCodeBlocks(canvas, size);
    _drawInlineCode(canvas, size);
    _drawImages(canvas, size);
    _drawSelectedBlankLines(canvas, size);
    canvas.restore();
    if (marginOpacity > 0.0) {
      _drawMarginLine(canvas, size);
    }
  }

  void _drawCodeBlocks(Canvas canvas, Size size) {
    if (codeBlocks.isEmpty) return;
    final fill = Paint()..color = codeBlockColor;
    final border = Paint()
      ..color = codeBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final block in codeBlocks) {
      final top = topPadding + block.top - scrollOffset;
      final bottom = topPadding + block.bottom - scrollOffset;
      if (bottom < 0 || top > size.height) continue;
      // Inset inside its rows so the card has air above and below it and never
      // touches the text around it; its rows (and the rules) are unchanged.
      final rect = Rect.fromLTRB(codeLeft, top + codeBlockInsetTop, codeRight > codeLeft ? codeRight : size.width, bottom - codeBlockInsetBottom);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect.deflate(0.5), border);
    }
  }

  /// Air between a code card and the rows above and below it. Glyphs sit in the
  /// lower part of a row, so the card is inset more at the top than the bottom to
  /// keep the padding around the code even.
  static const double codeBlockInsetTop = 4.0;
  static const double codeBlockInsetBottom = 0.0;

  void _drawImages(Canvas canvas, Size size) {
    if (imageBlocks.isEmpty) return;
    final photo = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    final border = Paint()
      ..color = codeBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final outline = Paint()
      ..color = imageAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final wash = Paint()..color = imageAccent.withValues(alpha: 0.18);
    final placeholder = Paint()..color = codeBlockColor;
    final right = imageRight > imageLeft ? imageRight : size.width;
    for (final block in imageBlocks) {
      final top = topPadding + block.top - scrollOffset + imageInset;
      final bottom = topPadding + block.bottom - scrollOffset - imageInset;
      if (bottom < 0 || top > size.height) continue;
      final area = Rect.fromLTRB(imageLeft, top, right, bottom);
      final image = imageCache?.peek(block.id);
      final selected = selectionStart >= 0 && block.touchedBy(selectionStart, selectionEnd);

      final Rect drawn;
      if (image != null) {
        drawn = imageDestination(area, Size(image.width.toDouble(), image.height.toDouble()));
        final rrect = RRect.fromRectAndRadius(drawn, const Radius.circular(10));
        canvas.save();
        canvas.clipRRect(rrect);
        final backdrop = imageCache?.inkOf(block.id)?.backdropFor(pageIsDark: pageIsDark);
        if (backdrop != null) canvas.drawRect(drawn, Paint()..color = backdrop);
        canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), drawn, photo);
        if (selected && selectionEnd > selectionStart) canvas.drawRect(drawn, wash);
        canvas.restore();
        canvas.drawRRect(rrect.deflate(0.5), border);
      } else {
        // Not decoded yet (or gone): a quiet card where the picture will be.
        drawn = Rect.fromLTWH(area.left, area.top, math.min(area.width, area.height * 1.4), area.height);
        final rrect = RRect.fromRectAndRadius(drawn, const Radius.circular(10));
        canvas.drawRRect(rrect, placeholder);
        canvas.drawRRect(rrect.deflate(0.5), border);
        if (block.id != pendingImageId && (imageCache?.hasFailed(block.id) ?? false)) {
          // A picture whose bytes are gone: a cross, so it reads as missing.
          final cross = Paint()
            ..color = codeBorderColor
            ..strokeWidth = 1.5;
          final c = drawn.center;
          final r = math.min(drawn.width, drawn.height) * 0.12;
          canvas.drawLine(c.translate(-r, -r), c.translate(r, r), cross);
          canvas.drawLine(c.translate(-r, r), c.translate(r, -r), cross);
        }
      }
      if (selected) canvas.drawRRect(RRect.fromRectAndRadius(drawn, const Radius.circular(10)).inflate(1), outline);
    }
  }

  void _drawInlineCode(Canvas canvas, Size size) {
    if (inlineCode.isEmpty) return;
    final fill = Paint()..color = inlineCodeColor;
    final border = Paint()
      ..color = codeBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final box in inlineCode) {
      final r = box.shift(Offset(inlineCodeLeft, topPadding - scrollOffset));
      if (r.bottom < 0 || r.top > size.height) continue;
      final rrect = RRect.fromRectAndRadius(Rect.fromLTRB(r.left - 1, r.top - 2, r.right + 1, r.bottom + 2), const Radius.circular(5));
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect.deflate(0.5), border);
    }
  }

  void _drawSelectedBlankLines(Canvas canvas, Size size) {
    if (selectedBlankLines.isEmpty || selectionBarWidth <= 0) return;
    final paint = Paint()..color = selectionColor;
    for (final line in selectedBlankLines) {
      final top = topPadding + line.top - scrollOffset;
      final bottom = topPadding + line.bottom - scrollOffset;
      if (bottom < 0 || top > size.height) continue;
      canvas.drawRect(Rect.fromLTRB(selectionBarLeft, top, selectionBarLeft + selectionBarWidth, bottom), paint);
    }
  }

  /// Index of the first entry in [lineBottoms] whose painted Y could
  /// fall at or below the top of the viewport — binary search since
  /// [lineBottoms] is sorted, so paint only visits lines actually on
  /// screen regardless of document length.
  int _firstVisibleIndex(double minBottom) {
    var lo = 0;
    var hi = lineBottoms.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (lineBottoms[mid] < minBottom) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _drawRuledLines(Canvas canvas, Size size) {
    final minBottom = scrollOffset - topPadding;
    var index = _firstVisibleIndex(minBottom);

    while (index < lineBottoms.length) {
      final bottom = lineBottoms[index];
      final top = index == 0 ? 0.0 : lineBottoms[index - 1];
      final topY = topPadding + top - scrollOffset;
      if (topY > size.height + 1.0) return;
      // A measured line that is several pitches tall (a heading) still gets
      // a rule at every pitch inside it, derived from the same measured
      // geometry the text was laid out with.
      final rows = math.max(1, ((bottom - top) / fallbackLineHeight).round());
      for (var j = rows - 1; j >= 0; j--) {
        final y = _snap(topPadding + bottom - j * fallbackLineHeight - scrollOffset);
        if (y > size.height + 1.0) return;
        if (y >= topPadding) {
          _drawOneLine(canvas, y, size.width);
        }
      }
      index++;
    }

    // Ran out of real content — keep going at a constant fallback
    // spacing for the blank "rest of the page" look.
    final lastBottom = lineBottoms.isEmpty ? 0.0 : lineBottoms.last;
    var y = topPadding + lastBottom - scrollOffset;
    // Advance to the first fallback line strictly after the last real
    // one, then continue at a constant interval from there.
    if (lineBottoms.isNotEmpty) y += fallbackLineHeight;
    while (y <= size.height + 1.0) {
      final snapped = _snap(y);
      if (snapped >= topPadding) {
        _drawOneLine(canvas, snapped, size.width);
      }
      y += fallbackLineHeight;
    }
  }

  double _snap(double y) => devicePixelRatio > 0
      ? (y * devicePixelRatio).roundToDouble() / devicePixelRatio
      : y;

  // A rule inside a code card is drawn at a third of its strength, so the card
  // reads as a surface on the paper with the ruling still faintly there.
  late final Paint _softLinePaint = Paint()
    ..color = lineColor.withValues(alpha: lineColor.a * 0.35)
    ..strokeWidth = _linePaint.strokeWidth
    ..isAntiAlias = false;

  // Whether a rule at document-space `docY` lies inside a code card or an image
  // block (its top edge excluded: that rule belongs to the line above). Such a
  // rule is drawn faintly, so the block reads as one object on the ruled paper
  // while the ruling stays faintly there beside and behind it.
  bool _insideCodeBlock(double docY) {
    for (final block in codeBlocks) {
      if (block.top > docY) break;
      if (docY > block.top + 0.5 && docY <= block.bottom + 0.5) return true;
    }
    for (final block in imageBlocks) {
      if (block.top > docY) break;
      if (docY > block.top + 0.5 && docY <= block.bottom + 0.5) return true;
    }
    return false;
  }

  void _drawOneLine(Canvas canvas, double y, double width) {
    final paint = _insideCodeBlock(y - topPadding + scrollOffset) ? _softLinePaint : _linePaint;
    if (lineStyle == RuledLineStyle.dashed) {
      _drawDashedLine(canvas, y, width, paint);
    } else {
      canvas.drawLine(Offset(0.0, y), Offset(width, y), paint);
    }
  }

  void _drawDashedLine(Canvas canvas, double y, double width, Paint paint) {
    const double dash = 8.0;
    const double gap = 5.0;
    double x = 0.0;
    while (x < width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  void _drawMarginLine(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(marginLineX, 0.0),
      Offset(marginLineX, size.height),
      _marginPaint,
    );
  }

  @override
  bool shouldRepaint(covariant RuledLinesPainter oldDelegate) =>
      !identical(oldDelegate.lineBottoms, lineBottoms) ||
      !identical(oldDelegate.codeBlocks, codeBlocks) ||
      !identical(oldDelegate.inlineCode, inlineCode) ||
      !identical(oldDelegate.imageBlocks, imageBlocks) ||
      !identical(oldDelegate.imageCache, imageCache) ||
      oldDelegate.pageIsDark != pageIsDark ||
      oldDelegate.imageLeft != imageLeft ||
      oldDelegate.imageRight != imageRight ||
      oldDelegate.selectionStart != selectionStart ||
      oldDelegate.selectionEnd != selectionEnd ||
      oldDelegate.imageAccent != imageAccent ||
      oldDelegate.inlineCodeColor != inlineCodeColor ||
      oldDelegate.codeBorderColor != codeBorderColor ||
      oldDelegate.inlineCodeLeft != inlineCodeLeft ||
      !_sameBlankLines(oldDelegate.selectedBlankLines, selectedBlankLines) ||
      oldDelegate.selectionColor != selectionColor ||
      oldDelegate.selectionBarLeft != selectionBarLeft ||
      oldDelegate.selectionBarWidth != selectionBarWidth ||
      oldDelegate.codeBlockColor != codeBlockColor ||
      oldDelegate.codeLeft != codeLeft ||
      oldDelegate.codeRight != codeRight ||
      oldDelegate.fallbackLineHeight != fallbackLineHeight ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.marginOpacity != marginOpacity ||
      oldDelegate.lineStyle != lineStyle ||
      oldDelegate.marginLineX != marginLineX ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.marginColor != marginColor;

  static bool _sameBlankLines(List<BlankLineRegion> a, List<BlankLineRegion> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].offset != b[i].offset || a[i].top != b[i].top || a[i].bottom != b[i].bottom) return false;
    }
    return true;
  }

  @override
  bool? hitTest(Offset position) => false;
}
