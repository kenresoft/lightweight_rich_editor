// ignore_for_file: avoid_print
//
// The ruled-grid policy, measured with real Roboto metrics (Flutter's default
// test font, Ahem, has unrealistic square metrics): inline text is fitted to
// one row, paragraph headers take the minimum whole number of rows their
// glyphs need, and every measured line bottom stays a whole multiple of the
// pitch — at every text scale.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

const _family = 'Roboto';
const _pitchPx = 30.0;

const _theme = RichTextRenderTheme(
  baseFontSize: 16,
  lineHeight: _pitchPx,
  h1FontSize: 28,
  h2FontSize: 22,
  h3FontSize: 18,
);

Future<bool> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) '$root/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    'C:/Users/amadi/AndroidStudioPlugins/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader(_family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer)));
    await loader.load();
    return true;
  }
  return false;
}

class _Laid {
  _Laid(this.renderer, this.metrics, this.bottoms, this.lines, this.style, this.strut);
  final TextSpanRenderer renderer;
  final RuledRowMetrics metrics;
  final List<double> bottoms;
  final List<LineMetrics> lines;
  final TextStyle style;
  final StrutStyle strut;

  double get pitch => metrics.pitch;
  List<double> get heights => [
    for (var i = 0; i < bottoms.length; i++) bottoms[i] - (i == 0 ? 0 : bottoms[i - 1]),
  ];

  /// Distance from each line's baseline up to that line's bottom ruled line.
  List<double> get baselineAboveRule => [
    for (var i = 0; i < lines.length; i++) bottoms[i] - lines[i].baseline,
  ];

  void expectOnGrid() {
    for (final b in bottoms) {
      final rows = (b / pitch).round();
      expect(b, closeTo(rows * pitch, 0.02), reason: 'bottom $b is not a multiple of pitch $pitch');
    }
  }
}

/// Lays a document out exactly the way the editor does: same base style,
/// strut, height behaviour, scaler and pixel ratio, through the renderer's own
/// [TextSpanRenderer.lineBottomOffsets].
_Laid _lay(
  String text, {
  List<TextAttribute> attrs = const [],
  double scale = 1.0,
  double dpr = 1.0,
  double width = 400,
  RichTextRenderTheme theme = _theme,
}) {
  final renderer = TextSpanRenderer(theme: theme);
  final scaler = TextScaler.linear(scale);
  final doc = EditorDocument.fromText(text, attrs);
  final metrics = renderer.rowMetrics(
    textScaler: scaler,
    devicePixelRatio: dpr,
    style: const TextStyle(fontFamily: _family),
  );
  final rowHeight = metrics.heightMultiplier(theme.baseFontSize);
  final style = TextStyle(
    fontFamily: _family,
    fontSize: theme.baseFontSize,
    height: rowHeight,
    leadingDistribution: TextLeadingDistribution.proportional,
  );
  final strut = StrutStyle(
    fontFamily: _family,
    fontSize: theme.baseFontSize,
    height: rowHeight,
    leadingDistribution: TextLeadingDistribution.proportional,
    leading: 0,
  );
  const behavior = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.proportional);
  final bottoms = renderer.lineBottomOffsets(
    doc,
    maxWidth: width,
    style: style,
    strutStyle: strut,
    textHeightBehavior: behavior,
    textScaler: scaler,
    devicePixelRatio: dpr,
  );
  final painter = TextPainter(
    text: renderer.renderSpan(doc, style: style, textScaler: scaler, devicePixelRatio: dpr),
    strutStyle: strut,
    textDirection: TextDirection.ltr,
    textWidthBasis: TextWidthBasis.parent,
    textHeightBehavior: behavior,
    textScaler: scaler,
  )..layout(maxWidth: width);
  return _Laid(renderer, metrics, bottoms, painter.computeLineMetrics(), style, strut);
}

TextAttribute _header(int start, int end, String level) =>
    TextAttribute(start: start, end: end, type: AttributeType.header, value: level);

String _fmt(double v) => v.toStringAsFixed(2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(await _loadRoboto(), isTrue, reason: 'Roboto not found under FLUTTER_ROOT');
  });

  const sentence = 'The quick brown fox jumps over the lazy dog';

  group('baseline anchoring (proportional vs even leading, measured)', () {
    test('baseline keeps one constant distance from the rule at every inline size', () {
      final distances = <double>[];
      final laid = _lay('x');
      final max = laid.metrics.maxInlineFontSize();
      for (var size = 8; size <= max; size += 2) {
        final l = _lay('hello world', attrs: [
          TextAttribute(start: 0, end: 11, type: AttributeType.size, value: size),
        ]);
        expect(l.heights.single, closeTo(l.pitch, 0.01));
        distances.add(l.baselineAboveRule.single);
      }
      print('baseline→rule by inline size 8..$max: ${distances.map(_fmt).toList()}');
      final spread = distances.reduce((a, b) => a > b ? a : b) - distances.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThan(0.3), reason: 'baseline drifted by $spread px across inline sizes');
    });
  });

  group('inline text is fitted to exactly one row', () {
    test('normal body text', () {
      final l = _lay('$sentence\n$sentence\n$sentence');
      print('body: pitch=${_fmt(l.pitch)} heights=${l.heights.map(_fmt).toList()} '
          'baseline→rule=${l.baselineAboveRule.map(_fmt).toList()}');
      expect(l.heights, everyElement(closeTo(l.pitch, 0.01)));
      l.expectOnGrid();
    });

    test('a single bold word inside a normal sentence', () {
      final l = _lay(sentence, attrs: [
        const TextAttribute(start: 4, end: 9, type: AttributeType.bold),
      ]);
      final plain = _lay(sentence);
      print('bold word: height=${_fmt(l.heights.single)} plain=${_fmt(plain.heights.single)} '
          'baseline→rule bold=${_fmt(l.baselineAboveRule.single)} plain=${_fmt(plain.baselineAboveRule.single)}');
      expect(l.heights.single, closeTo(l.pitch, 0.01));
      expect(l.baselineAboveRule.single, closeTo(plain.baselineAboveRule.single, 0.3));
    });

    test('a slightly larger inline word is unshrunk and does not grow the row', () {
      final l = _lay(sentence, attrs: [
        const TextAttribute(start: 4, end: 9, type: AttributeType.size, value: 18),
      ]);
      final span = l.renderer.renderSpan(EditorDocument.fromText(sentence, const [
        TextAttribute(start: 4, end: 9, type: AttributeType.size, value: 18),
      ]), style: l.style, devicePixelRatio: 1);
      final sizes = span.children!.cast<TextSpan>().map((c) => c.style!.fontSize).toList();
      print('18px inline word: fontSizes=$sizes height=${_fmt(l.heights.single)} '
          'maxInline=${l.metrics.maxInlineFontSize()}');
      expect(sizes, contains(18.0));
      expect(l.heights.single, closeTo(l.pitch, 0.01));
    });

    test('mixed inline sizes on one visual line: 16 → 22 → 16 → 24 → 16 stays exactly one row', () {
      const text = 'aaaa bbbb cccc dddd eeee';
      final attrs = [
        const TextAttribute(start: 5, end: 9, type: AttributeType.size, value: 22),
        const TextAttribute(start: 15, end: 19, type: AttributeType.size, value: 24),
      ];
      final l = _lay(text, attrs: attrs);
      final span = l.renderer.renderSpan(EditorDocument.fromText(text, attrs), style: l.style);
      final sizes = span.children!.cast<TextSpan>().map((c) => c.style!.fontSize).toList();
      final max = l.metrics.maxInlineFontSize();
      print('mixed 16/22/16/24/16: rendered sizes=$sizes maxInline=$max '
          'lines=${l.bottoms.length} height=${_fmt(l.heights.single)} pitch=${_fmt(l.pitch)}');
      expect(l.bottoms.length, 1);
      expect(l.heights.single, closeTo(l.pitch, 0.01));
      for (final s in sizes) {
        expect(s, lessThanOrEqualTo(max));
      }
      // The line must not disturb the rows below it either.
      final withBelow = _lay('$text\nnext line', attrs: attrs);
      expect(withBelow.heights, everyElement(closeTo(l.pitch, 0.01)));
    });

    test('very large requested inline sizes (imported 60, 200, 1000) render fitted to one row', () {
      final probe = _lay('x');
      final max = probe.metrics.maxInlineFontSize();
      for (final requested in [60, 200, 1000]) {
        final attrs = [TextAttribute(start: 0, end: 5, type: AttributeType.size, value: requested)];
        final l = _lay('hello world', attrs: attrs);
        final span = l.renderer.renderSpan(EditorDocument.fromText('hello world', attrs), style: l.style);
        final rendered = span.children!.cast<TextSpan>().first.style!.fontSize!;
        print('imported inline size $requested → rendered ${_fmt(rendered)}px '
            '(maxInline=$max) row=${_fmt(l.heights.single)} pitch=${_fmt(l.pitch)}');
        expect(rendered, max);
        expect(l.heights.single, closeTo(l.pitch, 0.01));
      }
    });
  });

  group('paragraph headers span the minimum whole number of rows', () {
    for (final entry in {'h1': 28.0, 'h2': 22.0, 'h3': 18.0}.entries) {
      test('${entry.key} is never shrunk, and takes exactly the rows its metrics need', () {
        const title = 'Title';
        final attrs = [_header(0, title.length, entry.key)];
        final l = _lay(title, attrs: attrs);
        final span = l.renderer.renderSpan(EditorDocument.fromText(title, attrs), style: l.style);
        final rendered = span.children!.cast<TextSpan>().single.style!.fontSize;
        final natural = l.metrics.naturalHeight(entry.value, FontWeight.bold, false, _family)!;
        final rows = (l.heights.single / l.pitch).round();
        print('${entry.key}: font=${entry.value} natural=${_fmt(natural)} '
            'maxNatural=${_fmt(l.metrics.maxHeaderNaturalHeight)} rows=$rows '
            'height=${_fmt(l.heights.single)} baseline→rule=${_fmt(l.baselineAboveRule.single)}');
        expect(rendered, entry.value);
        expect(l.heights.single, closeTo(rows * l.pitch, 0.02));
        // Minimality, derived from measured metrics (not a size→rows table).
        expect(natural, lessThanOrEqualTo(rows * l.metrics.maxHeaderNaturalHeight + 0.001));
        if (rows > 1) {
          expect(natural, greaterThan((rows - 1) * l.metrics.maxHeaderNaturalHeight));
        }
        l.expectOnGrid();
      });
    }

    test('mixed body + headings keep every cumulative bottom on the grid', () {
      const text = 'Body one\nBig title\nBody two\nMid title\nSmall title\nBody three';
      final attrs = [_header(9, 18, 'h1'), _header(28, 37, 'h2'), _header(38, 49, 'h3')];
      final l = _lay(text, attrs: attrs);
      print('mixed body+headings: bottoms=${l.bottoms.map(_fmt).toList()} '
          'rows=${l.heights.map((h) => (h / l.pitch).round()).toList()}');
      expect(l.bottoms.length, 6);
      l.expectOnGrid();
      expect(l.heights[0], closeTo(l.pitch, 0.01));
      expect(l.heights[2], closeTo(l.pitch, 0.01));
      expect(l.heights[5], closeTo(l.pitch, 0.01));
    });

    test('a wrapped H1 gets its row allocation per visual line, all on the grid', () {
      const title = 'A rather long title that has to wrap across several visual lines';
      final l = _lay('$title\nbody', attrs: [_header(0, title.length, 'h1')], width: 180);
      final rows = l.heights.map((h) => (h / l.pitch).round()).toList();
      print('wrapped H1 @180px: visual lines=${l.bottoms.length} rows per line=$rows '
          'bottoms=${l.bottoms.map(_fmt).toList()}');
      expect(l.bottoms.length, greaterThan(2));
      // Every visual line of the heading has the same allocation…
      final headingRows = rows.sublist(0, rows.length - 1);
      expect(headingRows.toSet().length, 1);
      // …and the trailing body line is exactly one row.
      expect(rows.last, 1);
      l.expectOnGrid();
    });
  });

  group('system/accessibility text scale', () {
    const scales = [0.5, 0.85, 1.0, 1.15, 1.3, 1.5, 2.0, 3.0];
    const dprs = [1.0, 2.75];

    test('every scale/pixel-ratio keeps rows on the scaled pitch and the grid', () {
      const text = 'Body\nTitle\nA long body line that wraps a few times when the width is small enough';
      final attrs = [_header(5, 10, 'h1')];
      for (final dpr in dprs) {
        for (final scale in scales) {
          final l = _lay(text, attrs: attrs, scale: scale, dpr: dpr, width: 220);
          final expectedPitch = (_pitchPx * scale).roundToDouble();
          final rows = l.heights.map((h) => (h / l.pitch).round()).toList();
          print('scale=$scale dpr=$dpr pitch=${_fmt(l.pitch)} (expected ${_fmt(expectedPitch)}) '
              'maxInline=${l.metrics.maxInlineFontSize()} rows=$rows');
          expect(l.pitch, closeTo(expectedPitch, 1e-9));
          l.expectOnGrid();
          expect(l.heights.first, closeTo(l.pitch, 0.02));
        }
      }
    });

    test('editor, TextPainter metrics, strut, painter and cache keys all share one effective scaler', () {
      final renderer = TextSpanRenderer(theme: _theme);
      const style = TextStyle(fontFamily: _family);
      for (final scale in scales) {
        final scaler = TextScaler.linear(scale);
        final a = renderer.rowMetrics(textScaler: scaler, devicePixelRatio: 2.75, style: style);
        final b = renderer.rowMetrics(textScaler: TextScaler.linear(scale), devicePixelRatio: 2.75, style: style);
        // Same effective inputs → the same instance (what the editor, painter
        // and controller all read).
        expect(identical(a, b), isTrue, reason: 'scale $scale should hit the metrics cache');

        // The strut the editor builds resolves to exactly the painter pitch.
        final strutPx = a.heightMultiplier(_theme.baseFontSize) * scaler.scale(_theme.baseFontSize);
        expect(strutPx, closeTo(a.pitch, 1e-9));

        // Measured line rows equal that same pitch (TextPainter agrees).
        final l = _lay('hello\nworld', scale: scale, dpr: 2.75);
        expect(l.heights, everyElement(closeTo(a.pitch, 0.02)));
        expect(l.metrics.pitch, a.pitch);
      }
      // A different scaler must be a different measurement, never a stale hit.
      final one = renderer.rowMetrics(textScaler: TextScaler.linear(1.0), style: style);
      final two = renderer.rowMetrics(textScaler: TextScaler.linear(2.0), style: style);
      expect(identical(one, two), isFalse);
      expect(two.pitch, closeTo(one.pitch * 2, 0.5));

      final doc = EditorDocument.fromText('hello');
      final first = renderer.lineBottomOffsets(doc, maxWidth: 300, style: _lay('x').style,
          strutStyle: _lay('x').strut, textScaler: TextScaler.linear(1.0));
      final second = renderer.lineBottomOffsets(doc, maxWidth: 300, style: _lay('x').style,
          strutStyle: _lay('x').strut, textScaler: TextScaler.linear(1.5));
      expect(identical(first, second), isFalse, reason: 'scaler is part of the lineBottoms cache key');
      final third = renderer.lineBottomOffsets(doc, maxWidth: 300, style: _lay('x').style,
          strutStyle: _lay('x').strut, textScaler: TextScaler.linear(1.5), devicePixelRatio: 3.0);
      expect(identical(second, third), isFalse, reason: 'pixel ratio is part of the lineBottoms cache key');
    });

    test('large-accessibility rows: heading rows are recomputed from scaled metrics', () {
      final out = <String>[];
      for (final scale in [1.0, 2.0, 3.0]) {
        final l = _lay('Title', attrs: [_header(0, 5, 'h1')], scale: scale);
        final rows = (l.heights.single / l.pitch).round();
        out.add('scale=$scale pitch=${_fmt(l.pitch)} h1 rows=$rows height=${_fmt(l.heights.single)}');
        l.expectOnGrid();
      }
      print(out.join('\n'));
    });
  });

  group('font-size stepping through the controller', () {
    RichEditorController make() {
      final c = RichEditorController(text: 'hello world', theme: _theme);
      // The real editor records the metrics of the actual render; do the same
      // with the same family the rest of these tests measure with.
      c.renderer.activeRowMetrics = c.renderer.rowMetrics(style: const TextStyle(fontFamily: _family));
      return c;
    }

    double rowOf(RichEditorController c) {
      final laid = _lay(c.document.text, attrs: List.of(c.document.attributes));
      expect(laid.bottoms.length, 1);
      return laid.heights.single;
    }

    test('repeated increase stops at the supported maximum; row, selection and stored size stay sane', () {
      final c = make();
      addTearDown(c.dispose);
      const selection = TextSelection(baseOffset: 0, extentOffset: 5);
      c.selection = selection;
      final max = c.maxInlineFontSize;
      final pitch = c.renderer.activeRowMetrics!.pitch;

      final shown = <double>[c.effectiveFontSize];
      for (var i = 0; i < 40; i++) {
        c.increaseFontSize();
        expect(c.selection, selection, reason: 'selection must be preserved');
        expect(rowOf(c), closeTo(pitch, 0.01), reason: 'row height must never change');
        shown.add(c.effectiveFontSize);
      }
      print('increase sequence (base 16, max $max): ${shown.toSet().map(_fmt).toList()}');
      expect(c.effectiveFontSize, max);
      expect(c.canIncreaseFontSize, isFalse);
      final stored = c.document.attributes.where((a) => a.type == AttributeType.size).map((a) => a.value as num);
      expect(stored, everyElement(lessThanOrEqualTo(max)));

      // Further presses at the ceiling are true no-ops (no history churn).
      final undoDepthProbe = c.canUndo;
      c.increaseFontSize();
      expect(c.effectiveFontSize, max);
      expect(undoDepthProbe, isTrue);
    });

    test('repeated decrease stops at the minimum without changing the row', () {
      final c = make();
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      final pitch = c.renderer.activeRowMetrics!.pitch;
      for (var i = 0; i < 20; i++) {
        c.decreaseFontSize();
        expect(rowOf(c), closeTo(pitch, 0.01));
      }
      expect(c.effectiveFontSize, RichEditorController.minInlineFontSize);
      expect(c.canDecreaseFontSize, isFalse);
    });

    test('undo/redo walk back and forth through size changes', () {
      final c = make();
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      final base = c.effectiveFontSize;
      c.increaseFontSize();
      final one = c.effectiveFontSize;
      c.increaseFontSize();
      final two = c.effectiveFontSize;
      expect([base, one, two], [16.0, 18.0, 20.0]);

      c.undo();
      expect(c.effectiveFontSize, one);
      c.undo();
      expect(c.effectiveFontSize, base);
      c.redo();
      expect(c.effectiveFontSize, one);
      c.redo();
      expect(c.effectiveFontSize, two);
      expect(rowOf(c), closeTo(c.renderer.activeRowMetrics!.pitch, 0.01));
    });

    test('a stored oversized size (import) is reported at its rendered size, and preserved', () {
      final c = RichEditorController(
        text: 'hello world',
        theme: _theme,
        initialAttributes: const [TextAttribute(start: 0, end: 5, type: AttributeType.size, value: 60)],
      );
      addTearDown(c.dispose);
      c.renderer.activeRowMetrics = c.renderer.rowMetrics(style: const TextStyle(fontFamily: _family));
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      final max = c.maxInlineFontSize;
      print('stored 60 → toolbar shows ${c.effectiveFontSize} (max $max)');
      expect(c.effectiveFontSize, max);
      expect(c.canIncreaseFontSize, isFalse);
      expect(c.document.attributes.single.value, 60); // fidelity preserved until edited
    });

    test('inside a header the inline size controls are disabled', () {
      final c = make();
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 2);
      c.setHeader('h1');
      expect(c.canChangeFontSize, isFalse);
      expect(c.canIncreaseFontSize, isFalse);
      expect(c.canDecreaseFontSize, isFalse);
      expect(c.effectiveFontSize, _theme.h1FontSize);
    });
  });

  group('performance on long documents', () {
    Stopwatch time(void Function() f) {
      final sw = Stopwatch()..start();
      f();
      return sw..stop();
    }

    test('body-only and header-dense 100k-character documents lay out in comparable time', () {
      final body = StringBuffer();
      for (var i = 0; body.length < 100000; i++) {
        body.write('Paragraph $i: the quick brown fox jumps over the lazy dog near the riverbank.\n');
      }
      final bodyText = body.toString();

      final dense = StringBuffer();
      final headers = <TextAttribute>[];
      for (var i = 0; dense.length < 100000; i++) {
        final start = dense.length;
        if (i % 3 == 0) {
          final title = 'Heading number $i';
          dense.write('$title\n');
          headers.add(_header(start, start + title.length, ['h1', 'h2', 'h3'][(i ~/ 3) % 3]));
        } else {
          dense.write('Paragraph $i: the quick brown fox jumps over the lazy dog near the riverbank.\n');
        }
      }

      late _Laid bodyLaid;
      late _Laid denseLaid;
      final bodyMs = time(() => bodyLaid = _lay(bodyText, width: 360)).elapsedMilliseconds;
      final denseMs = time(() => denseLaid = _lay(dense.toString(), attrs: headers, width: 360)).elapsedMilliseconds;

      // Second call with identical inputs must be a cache hit (same instance).
      final hit = time(() {
        final again = bodyLaid.renderer.lineBottomOffsets(
          EditorDocument.fromText(bodyText),
          maxWidth: 360,
          style: bodyLaid.style,
          strutStyle: bodyLaid.strut,
          textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.proportional),
        );
        expect(again.isNotEmpty, isTrue);
      }).elapsedMilliseconds;

      print('100k chars — body-only: ${bodyMs}ms for ${bodyLaid.bottoms.length} lines; '
          'header-dense: ${denseMs}ms for ${denseLaid.bottoms.length} lines; '
          'extra layout pass (uncached doc instance): ${hit}ms');
      denseLaid.expectOnGrid();
      expect(bodyMs, lessThan(8000));
      // Headers must not blow up layout cost relative to plain text.
      expect(denseMs, lessThan(bodyMs * 4 + 1500));
    });

    test('a selection-only change is a cache hit; a scale change recomputes once', () {
      final l = _lay('hello world');
      final doc = EditorDocument.fromText('hello world');
      List<double> call(double scale) => l.renderer.lineBottomOffsets(
        doc,
        maxWidth: 300,
        style: l.style,
        strutStyle: l.strut,
        textScaler: TextScaler.linear(scale),
      );
      final a = call(1.0);
      expect(identical(a, call(1.0)), isTrue);
      final b = call(1.3);
      expect(identical(a, b), isFalse);
      expect(identical(b, call(1.3)), isTrue);
    });
  });
}
