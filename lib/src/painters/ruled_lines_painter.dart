import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The style of ruled lines to draw in the background.
enum RuledLineStyle {
  /// No lines are drawn.
  none,

  /// Solid lines are drawn.
  solid,

  /// Dashed lines are drawn.
  dashed
}

/// A custom painter that draws notebook-style ruled lines and a margin line.
class RuledLinesPainter extends CustomPainter {
  /// Creates a [RuledLinesPainter].
  RuledLinesPainter({
    required this.lineHeight,
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

  /// The height between two horizontal lines.
  final double lineHeight;

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

  void _drawRuledLines(Canvas canvas, Size size) {
    final double firstY = topPadding + lineHeight - scrollOffset;
    final int skip = math.max(0, (-firstY / lineHeight).ceil());
    double y = firstY + skip * lineHeight;

    while (y <= size.height + 1.0) {
      if (y >= topPadding) {
        if (lineStyle == RuledLineStyle.dashed) {
          _drawDashedLine(canvas, y, size.width);
        } else {
          canvas.drawLine(Offset(0.0, y), Offset(size.width, y), _linePaint);
        }
      }
      y += lineHeight;
    }
  }

  void _drawDashedLine(Canvas canvas, double y, double width) {
    const double dash = 8.0;
    const double gap = 5.0;
    double x = 0.0;
    while (x < width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, width), y), _linePaint);
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
      oldDelegate.lineHeight != lineHeight ||
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
