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
  double devicePixelRatio = 1.0,
}) {
  return RuledLinesPainter(
    devicePixelRatio: devicePixelRatio,
    lineBottoms: lineBottoms,
    fallbackLineHeight: fallbackLineHeight,
    topPadding: topPadding,
    scrollOffset: scrollOffset,
    marginOpacity: marginOpacity,
    lineStyle: lineStyle,
    marginLineX: marginLineX,
  );
}

/// Records the y of every horizontal rule drawn (margin lines are vertical and
/// ignored); every other Canvas call is a no-op.
class _RecordingCanvas implements Canvas {
  final List<double> lineYs = [];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if (p1.dy == p2.dy) lineYs.add(p1.dy);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

  group('RuledLinesPainter — multi-row lines and pixel snapping', () {
    List<double> ruleYs(RuledLinesPainter painter, {double height = 200}) {
      final canvas = _RecordingCanvas();
      painter.paint(canvas, Size(400, height));
      return canvas.lineYs;
    }

    test('a line that is several pitches tall gets a rule at every pitch inside it', () {
      // Row 1 is one pitch; row 2 (a heading) is three pitches tall.
      final ys = ruleYs(_painter(
        lineBottoms: const [30, 120],
        fallbackLineHeight: 30,
        topPadding: 0,
        marginOpacity: 0,
      ));
      expect(ys.take(5).toList(), [30, 60, 90, 120, 150]);
    });

    test('a one-pitch-per-line document draws exactly the measured bottoms', () {
      final ys = ruleYs(_painter(
        lineBottoms: const [24, 48, 72],
        fallbackLineHeight: 24,
        topPadding: 0,
        marginOpacity: 0,
      ), height: 72);
      expect(ys, [24, 48, 72]);
    });

    test('interior rules of a partly scrolled heading still appear', () {
      final ys = ruleYs(_painter(
        lineBottoms: const [30, 120],
        fallbackLineHeight: 30,
        topPadding: 0,
        scrollOffset: 65,
        marginOpacity: 0,
      ), height: 100);
      // absolute rules 90, 120, 150 → 25, 55, 85 on screen (30/60 are above
      // the viewport's top edge).
      expect(ys.take(3).toList(), [25, 55, 85]);
    });

    test('rule y positions are snapped to the device pixel grid', () {
      const dpr = 2.75;
      final ys = ruleYs(_painter(
        lineBottoms: const [30, 60, 90],
        fallbackLineHeight: 30,
        topPadding: 0,
        marginOpacity: 0,
        devicePixelRatio: dpr,
      ), height: 100);
      expect(ys, isNotEmpty);
      for (final y in ys) {
        expect((y * dpr) % 1.0, anyOf(closeTo(0, 1e-9), closeTo(1, 1e-9)));
      }
    });

    test('shouldRepaint is true when devicePixelRatio differs', () {
      final shared = <double>[24, 48];
      final a = _painter(lineBottoms: shared);
      final b = _painter(lineBottoms: shared, devicePixelRatio: 3.0);
      expect(b.shouldRepaint(a), isTrue);
    });
  });

  group('RuledLinesPainter — hitTest', () {
    test('never claims hits, so it never intercepts touches meant for the text field', () {
      expect(_painter().hitTest(const Offset(10, 10)), isFalse);
    });
  });
}
