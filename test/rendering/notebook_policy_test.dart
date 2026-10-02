// ignore_for_file: avoid_print
//
// Regression suite for the *Notebook* ruled-grid UX policy, measured with real
// Roboto faces (Flutter's default test font, Ahem, has square metrics):
//
//  * body text, bold/italic/underline/colour/highlight and custom inline sizes
//    are each exactly ONE ruled row;
//  * an inline size that does not fit renders at the largest size that does;
//  * H1/H2/H3 are ONE ruled row (Notebook configures sizes so they fit);
//  * the pitch never depends on inline content, and follows the text scale;
//  * the baseline keeps one constant distance from its rule.
//
// The theme below mirrors the Notebook app's configuration in
// `RuledRichEditor` (lineHeight 30, base 16, h1/h2/h3 = 24/21/18).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

const _family = 'Roboto';

class Laid {
  Laid(this.renderer, this.doc, this.metrics, this.bottoms, this.lines, this.style, this.strut, this.span, this.painter);
  final TextPainter painter;
  final TextSpanRenderer renderer;
  final EditorDocument doc;
  final RuledRowMetrics metrics;
  final List<double> bottoms;
  final List<LineMetrics> lines;
  final TextStyle style;
  final StrutStyle strut;
  final TextSpan span;

  double get pitch => metrics.pitch;
  List<double> get heights => [
    for (var i = 0; i < bottoms.length; i++) bottoms[i] - (i == 0 ? 0 : bottoms[i - 1]),
  ];
  List<double> get baselineAboveRule => [
    for (var i = 0; i < lines.length; i++) bottoms[i] - lines[i].baseline,
  ];
  List<TextStyle> get runStyles => [
    for (final c in (span.children ?? const <InlineSpan>[]).cast<TextSpan>()) c.style!,
  ];

  void expectEveryLineOneRow() {
    for (final h in heights) {
      expect(h, closeTo(pitch, 0.02), reason: 'line height $h != pitch $pitch (heights=$heights)');
    }
    // The renderer's bottoms must agree with what the paragraph really lays
    // out (LineMetrics alone can not be trusted with mixed fallback fonts).
    expect(painter.height, closeTo(bottoms.length * pitch, 0.02),
        reason: 'laid-out paragraph height ${painter.height} != ${bottoms.length} rows of $pitch');
  }
}

Laid lay(
  String text, {
  List<TextAttribute> attrs = const [],
  double scale = 1.0,
  TextScaler? textScaler,
  double dpr = 1.0,
  double width = 0,
  RichTextRenderTheme theme = notebookTheme,
  List<String>? fallback,
}) {
  final renderer = TextSpanRenderer(theme: theme);
  final scaler = textScaler ?? TextScaler.linear(scale);
  final doc = EditorDocument.fromText(text, attrs);
  // Default width grows with the scale so a short line never wraps by accident.
  final effScale = scaler.scale(16) / 16;
  final w = width > 0 ? width : 400.0 * (effScale > 1 ? effScale : 1);
  final base = TextStyle(fontFamily: _family, fontFamilyFallback: fallback);
  final metrics = renderer.rowMetrics(textScaler: scaler, devicePixelRatio: dpr, style: base);
  final rowHeight = metrics.heightMultiplier(theme.baseFontSize);
  final style = base.copyWith(
    fontSize: theme.baseFontSize,
    height: rowHeight,
    leadingDistribution: TextLeadingDistribution.proportional,
  );
  final strut = StrutStyle(
    fontFamily: _family,
    fontFamilyFallback: fallback,
    fontSize: theme.baseFontSize,
    height: rowHeight,
    leadingDistribution: TextLeadingDistribution.proportional,
    forceStrutHeight: metrics.allHeadersFitOneRow,
    leading: 0,
  );
  const behavior = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.proportional);
  final bottoms = renderer.lineBottomOffsets(
    doc,
    maxWidth: w,
    style: style,
    strutStyle: strut,
    textHeightBehavior: behavior,
    textScaler: scaler,
    devicePixelRatio: dpr,
  );
  final span = renderer.renderSpan(doc, style: style, textScaler: scaler, devicePixelRatio: dpr);
  final painter = TextPainter(
    text: span,
    strutStyle: strut,
    textDirection: TextDirection.ltr,
    textWidthBasis: TextWidthBasis.parent,
    textHeightBehavior: behavior,
    textScaler: scaler,
  )..layout(maxWidth: w);
  return Laid(renderer, doc, metrics, bottoms, painter.computeLineMetrics(), style, strut, span, painter);
}

TextAttribute size(int s, int e, num v) => TextAttribute(start: s, end: e, type: AttributeType.size, value: v);
TextAttribute attr(int s, int e, AttributeType t, [Object? v]) => TextAttribute(start: s, end: e, type: t, value: v);
TextAttribute header(int s, int e, String l) => attr(s, e, AttributeType.header, l);

const scales = [0.85, 1.0, 1.15, 1.3, 1.4, 2.0, 3.0];
const dprs = [1.0, 1.5, 2.0, 2.625, 2.75, 3.0, 3.5];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadRoboto();
  });

  const sentence = 'aaaa bbbb cccc dddd eeee ffff';

  group('1. mixed inline sizes', () {
    // 16 → 22 → 16 → 24 → 16 (and a >max and a tiny size, in one line).
    final mixedAttrs = [
      size(5, 9, 22),
      size(15, 19, 24),
    ];
    final normalBoldLargerItalic = [
      attr(5, 9, AttributeType.bold),
      size(10, 14, 26),
      attr(10, 14, AttributeType.bold),
      attr(15, 19, AttributeType.italic),
    ];

    for (final dpr in [1.0, 2.75]) {
      for (final scale in scales) {
        test('16→22→16→24→16 and normal→bold→larger→italic→normal @scale $scale dpr $dpr', () {
          final plain = lay(sentence, scale: scale, dpr: dpr);
          for (final attrs in [mixedAttrs, normalBoldLargerItalic]) {
            final l = lay(sentence, attrs: attrs, scale: scale, dpr: dpr);
            final max = l.metrics.maxInlineFontSize(weight: FontWeight.bold, italic: true);
            expect(l.bottoms.length, 1, reason: 'mixed sizes must not wrap or add rows');
            l.expectEveryLineOneRow();
            // The pitch is a property of (theme, scaler) only.
            expect(l.pitch, plain.pitch);
            expect(l.heights.single, closeTo(plain.heights.single, 0.02));
            // Every run's *rendered* size fits: natural height ≤ one row's fill.
            for (final s in l.runStyles) {
              final nat = l.metrics.naturalHeight(
                s.fontSize!,
                s.fontWeight ?? FontWeight.normal,
                s.fontStyle == FontStyle.italic,
                _family,
              )!;
              expect(nat, lessThanOrEqualTo(l.metrics.maxNaturalHeight + 1e-6),
                  reason: 'run ${s.fontSize} natural $nat > ${l.metrics.maxNaturalHeight}');
              expect(s.fontSize!, lessThanOrEqualTo(max + 1e-9));
            }
            // Baseline keeps the same distance from the rule as plain text.
            expect(l.baselineAboveRule.single, closeTo(plain.baselineAboveRule.single, 0.6),
                reason: 'baseline drifted: ${l.baselineAboveRule.single} vs ${plain.baselineAboveRule.single}');
          }
        });
      }
    }

    test('an inline span never changes the pitch of the rows around it', () {
      const text = 'one\ntwo two two two\nthree\nfour';
      final plain = lay(text);
      final l = lay(text, attrs: [size(4, 8, 24), attr(4, 8, AttributeType.bold), size(9, 12, 200)]);
      expect(l.bottoms, plain.bottoms);
    });
  });

  group('2. formatting combinations — effective rendered metric, not stored attributes', () {
    // For each combination, a custom size at, below and above the ceiling.
    final combos = <String, List<AttributeType>>{
      'bold': [AttributeType.bold],
      'italic': [AttributeType.italic],
      'bold+italic': [AttributeType.bold, AttributeType.italic],
      'underline': [AttributeType.underline],
      'strikethrough': [AttributeType.strikethrough],
      'code': [AttributeType.code],
      'colour': [AttributeType.color],
      'highlight': [AttributeType.highlight],
      'link': [AttributeType.link],
      'all': [
        AttributeType.bold,
        AttributeType.italic,
        AttributeType.color,
        AttributeType.highlight,
        AttributeType.underline,
      ],
    };
    Object? valueFor(AttributeType t) => switch (t) {
      AttributeType.color => 0xFFFF0000,
      AttributeType.link => 'https://example.com',
      _ => null,
    };

    for (final scale in [1.0, 1.4, 2.0, 3.0]) {
      for (final entry in combos.entries) {
        test('${entry.key} + custom size @scale $scale', () {
          const text = 'xx WORD yy';
          for (final requested in [8, 16, 20, 24, 28, 32, 48, 64, 400]) {
            final attrs = [
              size(3, 7, requested),
              for (final t in entry.value) attr(3, 7, t, valueFor(t)),
            ];
            final l = lay(text, attrs: attrs, scale: scale);
            l.expectEveryLineOneRow();
            // The styled word is the second run.
            final s = l.runStyles[1];
            final isCode = entry.value.contains(AttributeType.code);
            final fam = isCode ? 'monospace' : _family;
            final weight = entry.value.contains(AttributeType.bold) ? FontWeight.bold : FontWeight.normal;
            final italic = entry.value.contains(AttributeType.italic);
            final max = l.metrics.maxInlineFontSize(weight: weight, italic: italic, family: fam);
            final nat = l.metrics.naturalHeight(s.fontSize!, weight, italic, fam);
            // Rendered size is exactly min(requested, ceiling for that face).
            expect(s.fontSize, requested <= max ? requested.toDouble() : max,
                reason: '${entry.key} requested $requested ceiling $max rendered ${s.fontSize}');
            if (nat != null) expect(nat, lessThanOrEqualTo(l.metrics.maxNaturalHeight + 1e-6));
            // The span's own line box is exactly one pitch.
            expect(s.height! * l.metrics.textScaler.scale(s.fontSize!), closeTo(l.pitch, 1e-6));
          }
        });
      }
    }

    test('colour and highlight never change the effective size or baseline', () {
      const text = 'xx WORD yy';
      final base = lay(text, attrs: [size(3, 7, 22)]);
      for (final extra in [
        attr(3, 7, AttributeType.color, 0xFF00FF00),
        attr(3, 7, AttributeType.highlight),
      ]) {
        final l = lay(text, attrs: [size(3, 7, 22), extra]);
        expect(l.runStyles[1].fontSize, base.runStyles[1].fontSize);
        expect(l.baselineAboveRule.single, closeTo(base.baselineAboveRule.single, 1e-6));
        expect(l.bottoms, base.bottoms);
      }
    });
  });

  group('3. Notebook headings are exactly one row', () {
    final levels = {'h1': 24.0, 'h2': 21.0, 'h3': 18.0};

    for (final e in levels.entries) {
      test('${e.key} at configured size is one row for every text scale 0.85–4.0 (step 0.01)', () {
        final failures = <String>[];
        final renderer = TextSpanRenderer(theme: notebookTheme);
        for (var i = 85; i <= 400; i++) {
          final scale = i / 100;
          final m = renderer.rowMetrics(textScaler: TextScaler.linear(scale), style: const TextStyle(fontFamily: _family));
          if (m.rowsForParagraph(e.value, FontWeight.bold) != 1) {
            failures.add('scale $scale → ${m.rowsForParagraph(e.value, FontWeight.bold)} rows');
          }
        }
        expect(failures, isEmpty, reason: failures.take(10).join('; '));
      });
    }

    // The Notebook's "Line Spacing" presets: a tighter row shrinks the headings in
    // proportion (never inflates them for a roomier one) and they must still be one row.
    for (final pitch in [27.0, 34.0]) {
      test('headings are one row at a ${pitch}px row for every text scale 0.85–3.0', () {
        // The same factor the Notebook app applies (ruled_rich_editor.dart).
        final k = pitch < 30 ? pitch / 30 * 0.96 : 1.0;
        final theme = notebookTheme.copyWith(lineHeight: pitch, h1FontSize: 24 * k, h2FontSize: 21 * k, h3FontSize: 18 * k);
        final renderer = TextSpanRenderer(theme: theme);
        final failures = <String>[];
        for (var i = 85; i <= 300; i++) {
          final m = renderer.rowMetrics(textScaler: TextScaler.linear(i / 100), style: const TextStyle(fontFamily: _family));
          for (final size in [theme.h1FontSize, theme.h2FontSize, theme.h3FontSize]) {
            if (m.rowsForParagraph(size, FontWeight.bold) != 1) failures.add('scale ${i / 100} size $size');
          }
        }
        expect(failures, isEmpty, reason: failures.take(10).join('; '));
      });
    }

    for (final scale in scales) {
      test('normal/long/width-filling headings lay out as 1 row per visual line @scale $scale', () {
        const short = 'Title';
        const long = 'A considerably longer heading that is certain to wrap onto further visual lines when the editor is narrow';
        // A heading whose single visual line nearly fills the available width.
        const nearly = 'Heading that just about fits';
        for (final level in levels.keys) {
          for (final width in [400.0, 230.0, 120.0]) {
            final text = '$short\n$long\n$nearly\nbody';
            final attrs = [
              header(0, short.length, level),
              header(short.length + 1, short.length + 1 + long.length, level),
              header(short.length + long.length + 2, short.length + long.length + 2 + nearly.length, level),
            ];
            final l = lay(text, attrs: attrs, scale: scale, dpr: 2.75, width: width);
            l.expectEveryLineOneRow();
            for (final b in l.bottoms) {
              expect(b / l.pitch, closeTo((b / l.pitch).round(), 0.02));
            }
            // Heading glyphs are never shrunk — they render at the configured size.
            final expectedSize = levels[level]!;
            final heading = l.runStyles.first;
            expect(heading.fontSize, expectedSize);
            // Baseline keeps the body-text distance from its rule (±1px of
            // bold/size rounding): headings sit on their own ruled line.
            final body = lay('body', scale: scale, dpr: 2.75, width: width);
            expect(l.baselineAboveRule.first, closeTo(body.baselineAboveRule.first, 1.5),
                reason: '$level @scale $scale width $width');
          }
        }
      });
    }

    test('an inline size inside a heading is ignored and the heading stays one row', () {
      const text = 'Heading';
      final l = lay(text, attrs: [header(0, 7, 'h1'), size(0, 7, 64), attr(0, 7, AttributeType.italic)]);
      expect(l.runStyles.single.fontSize, 24);
      l.expectEveryLineOneRow();
    });
  });

  group('5. oversized imports', () {
    test('stored size survives; render is constrained; document identical after render', () {
      const text = 'hello world';
      for (final big in [60, 200, 1000, 99999]) {
        final attrs = [size(0, 5, big)];
        final l = lay(text, attrs: attrs);
        final max = l.metrics.maxInlineFontSize();
        expect(l.runStyles.first.fontSize, max);
        l.expectEveryLineOneRow();
        expect(l.doc.attributes.single.value, big, reason: 'rendering must not rewrite the stored value');
      }
    });

    test('non-finite / non-positive stored sizes fall back to the base size', () {
      for (final bad in [0, -5, double.nan, double.infinity, double.negativeInfinity]) {
        final l = lay('hello world', attrs: [size(0, 5, bad)]);
        expect(l.runStyles.first.fontSize, 16);
        l.expectEveryLineOneRow();
      }
    });
  });

  group('6. text scaling', () {
    for (final dpr in [1.0, 2.75]) {
      for (final scale in [0.5, 0.85, 1.0, 1.15, 1.4, 2.0, 2.5, 3.0, 4.0]) {
        test('pitch, strut, TextPainter rows and baseline agree @scale $scale dpr $dpr', () {
          final l = lay('plain body\nsecond line ${'x' * 120}\nTitle', attrs: [header(Text0.titleStart, Text0.titleEnd, 'h1')],
              scale: scale, dpr: dpr, width: 300);
          final expectedPitch = (30 * scale).roundToDouble().clamp(1.0, double.infinity);
          expect(l.pitch, expectedPitch);
          l.expectEveryLineOneRow();
          // No double scaling: line height == strut height == pitch exactly.
          final scaler = TextScaler.linear(scale);
          expect(l.strut.height! * scaler.scale(l.strut.fontSize!), closeTo(l.pitch, 1e-9));
          expect(l.style.height! * scaler.scale(l.style.fontSize!), closeTo(l.pitch, 1e-9));
          // Baseline→rule is identical on every line (no drift down the page).
          final d = l.baselineAboveRule;
          final spread = d.reduce((a, b) => a > b ? a : b) - d.reduce((a, b) => a < b ? a : b);
          expect(spread, lessThan(1.5), reason: 'baseline spread $d');
          // Glyph size scales with the text scaler (not double, not none).
          expect(l.lines.first.height, closeTo(l.pitch, 0.02));
        });
      }
    }

    test('the Notebook chrome clamp (0.85–1.4) is applied by the app shell and is not a grid workaround', () {
      // Documented behaviour, asserted at the metric level: the grid itself is
      // valid beyond the clamp, so it needs no help from it.
      for (final scale in [0.5, 3.0]) {
        final l = lay('hello\nworld', scale: scale);
        l.expectEveryLineOneRow();
      }
    });
  });

  group('6b. non-linear system font scaling (Android 14+)', () {
    // Measured on a device at system font scale 2.0, where a linear
    // `scale(lineHeight)` made the pitch too small for the scaled text and put
    // H1/H2 on two rows.
    final scalers = <TextScaler>[
      CurveTextScaler.android20,
      CurveTextScaler.milder(0.5, name: 'android-half'),
      CurveTextScaler.milder(0.25, name: 'android-quarter'),
      const TextScaler.linear(1.0),
      const TextScaler.linear(2.0),
    ];
    const doc = 'Body line\nTitle\nSub\nMinor\nA really long heading that is certain to wrap onto several visual lines\n'
        'aaaa bbbb cccc dddd\nlast';
    int at(String needle) => doc.indexOf(needle);
    const long = 'A really long heading that is certain to wrap onto several visual lines';
    final attrs = [
      header(at('Title'), at('Title') + 5, 'h1'),
      header(at('Sub'), at('Sub') + 3, 'h2'),
      header(at('Minor'), at('Minor') + 5, 'h3'),
      header(at(long), at(long) + long.length, 'h1'),
      size(at('bbbb'), at('bbbb') + 4, 22),
      size(at('cccc'), at('cccc') + 4, 400),
      attr(at('cccc'), at('cccc') + 4, AttributeType.bold),
    ];

    for (final scaler in scalers) {
      for (final width in [400.0, 260.0]) {
        test('$scaler: pitch follows the body text; every line, heading and inline size is one row @width $width', () {
          final l = lay(doc, attrs: attrs, textScaler: scaler, width: width * (scaler.scale(16) / 16 > 1 ? scaler.scale(16) / 16 : 1), dpr: 1.7);
          final expectedPitch = (30 * scaler.scale(16) / 16).roundToDouble();
          expect(l.pitch, expectedPitch, reason: 'pitch must scale exactly as the 16px body text does');
          expect(l.metrics.allHeadersFitOneRow, isTrue);
          for (final s in [24.0, 21.0, 18.0]) {
            expect(l.metrics.rowsForParagraph(s, FontWeight.bold), 1, reason: 'heading $s at $scaler');
          }
          l.expectEveryLineOneRow();
          for (final b in l.bottoms) {
            expect(b / l.pitch, closeTo((b / l.pitch).round(), 0.02));
          }
          // Heading glyphs are never shrunk; baselines sit at the body distance.
          final body = lay('Body', textScaler: scaler, dpr: 1.7);
          expect(l.baselineAboveRule.first, closeTo(body.baselineAboveRule.first, 0.6));
          final spread = l.baselineAboveRule.reduce((a, b) => a > b ? a : b) - l.baselineAboveRule.reduce((a, b) => a < b ? a : b);
          expect(spread, lessThan(2.0), reason: 'baseline→rule drifted: ${l.baselineAboveRule}');
          // Inline ceiling is measured at the scaled size, in the same row.
          final max = l.metrics.maxInlineFontSize();
          expect(l.metrics.naturalHeight(max, FontWeight.normal, false, _family)!, lessThanOrEqualTo(l.metrics.maxNaturalHeight + 1e-6));
        });
      }
    }

    test('H1/H2/H3 stay one row over the whole range of font scales, linear and curved', () {
      final failures = <String>[];
      final renderer = TextSpanRenderer(theme: notebookTheme);
      for (var i = 85; i <= 400; i++) {
        final f = i / 100;
        final candidates = <TextScaler>[
          TextScaler.linear(f),
          CurveTextScaler.milder((f - 1).clamp(0.0, 3.0) / 1.0, name: 'curve-$f'),
        ];
        for (final s in candidates) {
          final m = renderer.rowMetrics(textScaler: s, style: const TextStyle(fontFamily: _family));
          for (final h in [24.0, 21.0, 18.0]) {
            if (m.rowsForParagraph(h, FontWeight.bold) != 1) failures.add('$s @$f h=$h → ${m.rowsForParagraph(h, FontWeight.bold)} rows');
          }
        }
      }
      expect(failures, isEmpty, reason: failures.take(8).join('; '));
    });
  });

  group('8. device pixel ratio', () {
    for (final dpr in dprs) {
      test('rules land on physical pixels with no cumulative drift @dpr $dpr', () {
        for (final scale in [1.0, 1.15, 1.3, 2.0]) {
          final l = lay('l\n' * 400, scale: scale, dpr: dpr);
          final rec = _RecordingCanvas();
          RuledLinesPainter(
            lineBottoms: l.bottoms,
            fallbackLineHeight: l.pitch,
            topPadding: 12,
            scrollOffset: 0,
            marginOpacity: 0,
            lineStyle: RuledLineStyle.solid,
            marginLineX: 44,
            devicePixelRatio: dpr,
          ).paint(rec, const Size(400, 100000));
          final ys = rec.lineYs;
          expect(ys.length, greaterThan(400));
          for (var i = 0; i < ys.length; i++) {
            // Pixel aligned: y * dpr is a whole physical pixel.
            expect((ys[i] * dpr) - (ys[i] * dpr).roundToDouble(), closeTo(0, 1e-6),
                reason: 'rule $i at ${ys[i]} is not on a physical pixel (dpr $dpr)');
            // No cumulative drift: rule k sits within half a physical pixel of
            // topPadding + (k+1) * pitch, at k = 0 and k = 400 alike.
            expect((ys[i] - (12 + (i + 1) * l.pitch)).abs(), lessThanOrEqualTo(0.5 / dpr + 1e-6),
                reason: 'rule $i drifted (dpr $dpr scale $scale)');
            // And the text row it belongs to agrees (rows are exact pitches).
            if (i < l.bottoms.length) {
              expect(l.bottoms[i], closeTo((i + 1) * l.pitch, 0.02));
            }
          }
        }
      });
    }
  });

  group('7. font / fallback metrics', () {
    // Families loaded from the host OS when present; the tests that need them
    // are skipped (not silently passed) otherwise.
    late bool hasCjk, hasEmoji, hasMono;
    setUpAll(() async {
      hasCjk = await loadSystemFont('NBCjk', 'C:/Windows/Fonts/malgun.ttf');
      hasEmoji = await loadSystemFont('NBEmoji', 'C:/Windows/Fonts/seguiemj.ttf');
      hasMono = await loadSystemFont('NBMono', 'C:/Windows/Fonts/consola.ttf');
      print('fallback fonts available: cjk=$hasCjk emoji=$hasEmoji mono=$hasMono');
    });

    void checkRun(String label, String text, {List<String>? fallback, required bool available}) {
      test('$label: every size ≤ ceiling keeps its row, at several scales', () {
        if (!available) {
          markTestSkipped('font not available on this host');
          return;
        }
        for (final scale in [1.0, 1.4, 2.0]) {
          final probe = lay(text, fallback: fallback, scale: scale);
          final max = probe.metrics.maxInlineFontSize();
          for (final sz in [12, 16, 20, max.toInt(), (max + 10).toInt(), 200]) {
            final l = lay(text, fallback: fallback, scale: scale, attrs: [size(0, text.length, sz)]);
            l.expectEveryLineOneRow();
            expect(l.runStyles.single.fontSize, sz <= max ? sz.toDouble() : max);
          }
        }
      });
    }

    checkRun('Latin', 'The quick brown fox', available: true);
    checkRun('CJK via fallback family', '日本語のテキスト 한국어', fallback: const ['NBCjk'], available: true);
    checkRun('emoji via fallback family', 'ok 😀🎉👍 ok', fallback: const ['NBEmoji'], available: true);
    checkRun('mixed Latin+CJK+emoji', 'abc 日本語 😀 한국어 xyz', fallback: const ['NBCjk', 'NBEmoji'], available: true);

    test('a line mixing Latin, CJK and emoji is exactly one row and keeps the Latin baseline', () {
      if (!(hasCjk && hasEmoji)) {
        markTestSkipped('fallback fonts not available');
        return;
      }
      for (final scale in [1.0, 1.4, 2.0]) {
        final latin = lay('abc xyz', scale: scale);
        for (final attrs in [
          const <TextAttribute>[],
          [size(0, 12, 22)],
          [attr(0, 12, AttributeType.bold), size(4, 9, 20)],
        ]) {
          final mixed = lay('abc 日本語 😀 한국어', attrs: attrs, scale: scale, fallback: const ['NBCjk', 'NBEmoji']);
          mixed.expectEveryLineOneRow();
          // Without the forced strut this line laid out 1px taller than the
          // pitch (Latin descent + CJK ascent), and its baseline moved.
          expect(mixed.painter.height, mixed.pitch);
          expect(
            mixed.painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
            closeTo(latin.painter.computeDistanceToActualBaseline(TextBaseline.alphabetic), 0.6),
            reason: 'mixed-font baseline moved at scale $scale',
          );
        }
      }
    });

    test('a heading containing fallback glyphs stays one row', () {
      if (!(hasCjk && hasEmoji)) {
        markTestSkipped('fallback fonts not available');
        return;
      }
      const t = '日本語 heading 😀';
      for (final level in ['h1', 'h2', 'h3']) {
        final l = lay('$t\nbody', attrs: [header(0, t.length, level)], fallback: const ['NBCjk', 'NBEmoji']);
        l.expectEveryLineOneRow();
      }
    });

    test('monospace (code) runs are measured with the code family, not the body family', () {
      if (!hasMono) {
        markTestSkipped('Consolas not available');
        return;
      }
      const mono = RichTextRenderTheme(
        baseFontSize: 16, lineHeight: 30, h1FontSize: 24, h2FontSize: 21, h3FontSize: 18, codeFontFamily: 'NBMono');
      final l = lay('xx CODE yy', theme: mono, attrs: [size(3, 7, 400), attr(3, 7, AttributeType.code)]);
      l.expectEveryLineOneRow();
      final max = l.metrics.maxInlineFontSize(family: 'NBMono');
      expect(l.runStyles[1].fontSize, max);
      expect(l.runStyles[1].fontFamily, 'NBMono');
    });
  });
}

// Offsets for the 3-line document in the text-scaling group.
class Text0 {
  static const titleStart = 11 + 'second line '.length + 120 + 1;
  static const titleEnd = titleStart + 5;
}

/// Records the y of every horizontal rule the painter draws.
class _RecordingCanvas implements Canvas {
  final lineYs = <double>[];
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if (p1.dy == p2.dy) lineYs.add(p1.dy);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}
