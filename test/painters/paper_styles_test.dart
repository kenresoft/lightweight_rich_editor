// Graph paper and a dot grid: the rules (grid) or dots at the crossings, drawn without errors.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/painters/ruled_lines_painter.dart';

RuledLinesPainter _painter(RuledLineStyle style) => RuledLinesPainter(
      devicePixelRatio: 1.0,
      lineBottoms: const [24, 48, 72],
      fallbackLineHeight: 24,
      topPadding: 12,
      scrollOffset: 0,
      marginOpacity: 1,
      lineStyle: style,
      marginLineX: 44,
    );

class _Count implements Canvas {
  int horizontal = 0;
  int vertical = 0;
  int points = 0;

  @override
  void drawLine(Offset a, Offset b, Paint p) {
    if (a.dy == b.dy) horizontal++;
    if (a.dx == b.dx) vertical++;
  }

  @override
  void drawPoints(PointMode mode, List<Offset> pts, Paint paint) => points += pts.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('grid: the rules plus vertical lines a row apart', () {
    final c = _Count();
    _painter(RuledLineStyle.grid).paint(c, const Size(240, 200));
    expect(c.horizontal, greaterThan(0));
    expect(c.vertical, greaterThanOrEqualTo(9), reason: 'a column every 24px across 240px, and the margin');
  });

  test('dots: points, no long rules', () {
    final c = _Count();
    _painter(RuledLineStyle.dots).paint(c, const Size(240, 200));
    expect(c.points, greaterThan(20));
    expect(c.horizontal, 0);
  });

  test('solid and none are as before', () {
    final solid = _Count();
    _painter(RuledLineStyle.solid).paint(solid, const Size(240, 200));
    expect(solid.horizontal, greaterThan(0));
    expect(solid.points, 0);
    final none = _Count();
    _painter(RuledLineStyle.none).paint(none, const Size(240, 200));
    expect(none.horizontal, 0);
  });
}
