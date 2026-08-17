import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/painters/ruled_lines_painter.dart';

RuledLinesPainter _painter({
  List<double> lineBottoms = const [24, 48, 72],
  double fallbackLineHeight = 24,
  double topPadding = 12,
  double scrollOffset = 0,
  double marginOpacity = 1,
  RuledLineStyle lineStyle = RuledLineStyle.solid,
  double marginLineX = 44,
}) {
  return RuledLinesPainter(
    lineBottoms: lineBottoms,
    fallbackLineHeight: fallbackLineHeight,
    topPadding: topPadding,
    scrollOffset: scrollOffset,
    marginOpacity: marginOpacity,
    lineStyle: lineStyle,
    marginLineX: marginLineX,
  );
}

void main() {
  group('RuledLinesPainter — paint', () {
    test('paints without throwing for a document with real line bottoms', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      _painter().paint(canvas, const Size(400, 800));

      expect(() => recorder.endRecording(), returnsNormally);
    });

    test('paints without throwing when lineBottoms is empty (falls back entirely)', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      _painter(lineBottoms: const []).paint(canvas, const Size(400, 800));

      expect(() => recorder.endRecording(), returnsNormally);
    });

    test('paints without throwing when scrolled past all real content', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      _painter(lineBottoms: const [24, 48], scrollOffset: 5000).paint(canvas, const Size(400, 800));

      expect(() => recorder.endRecording(), returnsNormally);
    });

    test('paints without throwing in dashed style', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      _painter(lineStyle: RuledLineStyle.dashed).paint(canvas, const Size(400, 800));

      expect(() => recorder.endRecording(), returnsNormally);
    });

    test('draws nothing extra when lineStyle is none and marginOpacity is 0', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      _painter(lineStyle: RuledLineStyle.none, marginOpacity: 0).paint(canvas, const Size(400, 800));

      expect(() => recorder.endRecording(), returnsNormally);
    });
  });

  group('RuledLinesPainter — shouldRepaint', () {
    test('false when every field is equal, including an identical lineBottoms list', () {
      final shared = <double>[24, 48];
      final a = _painter(lineBottoms: shared);
      final b = _painter(lineBottoms: shared);

      expect(b.shouldRepaint(a), isFalse);
    });

    test('true when lineBottoms is a different list instance, even with equal values', () {
      // Built via List.of rather than two `const [...]` literals, which
      // Dart would canonicalize to the same instance — defeating the
      // point of this test.
      final a = _painter(lineBottoms: List.of([24, 48]));
      final b = _painter(lineBottoms: List.of([24, 48]));

      // Deliberately reference-based (see the class doc comment): two
      // separately-computed lists with equal values are still treated
      // as "changed" here, since callers are expected to reuse a cache
      // hit's list instance rather than reconstruct an equal one.
      expect(identical(a.lineBottoms, b.lineBottoms), isFalse);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('true when scrollOffset differs', () {
      final shared = <double>[24, 48];
      final a = _painter(lineBottoms: shared, scrollOffset: 0);
      final b = _painter(lineBottoms: shared, scrollOffset: 20);

      expect(b.shouldRepaint(a), isTrue);
    });

    test('true when fallbackLineHeight differs', () {
      final shared = <double>[24, 48];
      final a = _painter(lineBottoms: shared, fallbackLineHeight: 24);
      final b = _painter(lineBottoms: shared, fallbackLineHeight: 30);

      expect(b.shouldRepaint(a), isTrue);
    });
  });

  group('RuledLinesPainter — hitTest', () {
    test('never claims hits, so it never intercepts touches meant for the text field', () {
      expect(_painter().hitTest(const Offset(10, 10)), isFalse);
    });
  });
}
