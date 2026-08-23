import 'dart:math' as math;
import 'package:flutter/material.dart';

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
    this.lineColor = const Color(0x66607D8B),
    this.marginColor = const Color(0xCCFFCDD2),
  }) {
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

  /// The constant spacing continued below the last entry in
  /// [lineBottoms], for the blank ruled space past wherever the
  /// document's actual content ends.
  final double fallbackLineHeight;

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
    if (lineStyle != RuledLineStyle.none) {
      _drawRuledLines(canvas, size);
    }
    if (marginOpacity > 0.0) {
      _drawMarginLine(canvas, size);
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
      final y = topPadding + lineBottoms[index] - scrollOffset;
      if (y > size.height + 1.0) return;
      if (y >= topPadding) _drawOneLine(canvas, y, size.width);
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
      if (y >= topPadding) _drawOneLine(canvas, y, size.width);
      y += fallbackLineHeight;
    }
  }

  void _drawOneLine(Canvas canvas, double y, double width) {
    if (lineStyle == RuledLineStyle.dashed) {
      _drawDashedLine(canvas, y, width);
    } else {
      canvas.drawLine(Offset(0.0, y), Offset(width, y), _linePaint);
    }
  }

  void _drawDashedLine(Canvas canvas, double y, double width) {
    const double dash = 8.0;
    const double gap = 5.0;
    double x = 0.0;
    while (x < width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, width), y),
        _linePaint,
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
      oldDelegate.fallbackLineHeight != fallbackLineHeight ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.marginOpacity != marginOpacity ||
      oldDelegate.lineStyle != lineStyle ||
      oldDelegate.marginLineX != marginLineX ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.marginColor != marginColor;

  @override
  bool? hitTest(Offset position) => false;
}
