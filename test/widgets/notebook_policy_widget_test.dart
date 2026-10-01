// ignore_for_file: avoid_print
//
// The mounted editor (real `TextField`, real Roboto, Notebook theme) must lay
// out exactly the rows the metrics predict: same pitch, same row bottoms as the
// ruled-lines painter, no double scaling, at accessibility text scales and
// fractional pixel ratios.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

Future<void> _pump(
  WidgetTester tester,
  RichEditorController controller,
  ScrollController scroll, {
  double scale = 1.0,
  TextScaler? scaler,
  required double dpr,
  double width = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler ?? TextScaler.linear(scale), devicePixelRatio: dpr),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 30000,
          child: RichTextEditor(controller: controller, scrollController: scroll, autofocus: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _body = 'plain body line';
const _mixed = 'aaaa bbbb cccc dddd eeee';
const _h1 = 'Big heading';
const _h2 = 'Medium heading';
const _h3 = 'Small heading';
const _long = 'A long paragraph that keeps going and going so it has to wrap across several visual lines of the ruled page.';
const _longHeading = 'A really long heading that is certain to wrap onto several visual lines when the page is narrow';

RichEditorController _notebookController() {
  final text = [_body, _mixed, _h1, _h2, _h3, _longHeading, _long, '1234567890 ' * 8].join('\n');
  var o = 0;
  int start(String s) {
    final at = text.indexOf(s, o);
    o = at + s.length;
    return at;
  }

  start(_body);
  final m = start(_mixed);
  final h1 = start(_h1);
  final h2 = start(_h2);
  final h3 = start(_h3);
  final hl = start(_longHeading);
  return RichEditorController(
    text: text,
    theme: notebookTheme,
    initialAttributes: [
      TextAttribute(start: m + 5, end: m + 9, type: AttributeType.size, value: 22),
      TextAttribute(start: m + 15, end: m + 19, type: AttributeType.size, value: 24),
      TextAttribute(start: m + 10, end: m + 14, type: AttributeType.bold),
      TextAttribute(start: m + 10, end: m + 14, type: AttributeType.size, value: 400), // oversized import
      TextAttribute(start: m + 20, end: m + 24, type: AttributeType.italic),
      TextAttribute(start: h1, end: h1 + _h1.length, type: AttributeType.header, value: 'h1'),
      TextAttribute(start: h2, end: h2 + _h2.length, type: AttributeType.header, value: 'h2'),
      TextAttribute(start: h3, end: h3 + _h3.length, type: AttributeType.header, value: 'h3'),
      TextAttribute(start: hl, end: hl + _longHeading.length, type: AttributeType.header, value: 'h1'),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);

  for (final dpr in [1.0, 2.625, 3.0]) {
    for (final scaler in <TextScaler>[
      const TextScaler.linear(0.85),
      const TextScaler.linear(1.0),
      const TextScaler.linear(1.4),
      const TextScaler.linear(2.0),
      const TextScaler.linear(3.0),
      CurveTextScaler.android20,
    ]) {
      final scale = scaler.scale(16) / 16;
      for (final width in [400.0, 240.0]) {
        testWidgets('mounted rows == metric rows @${scaler is CurveTextScaler ? scaler : 'scale $scale'} dpr $dpr width $width', (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = const Size(1000, 30000);
          addTearDown(tester.view.reset);
          final controller = _notebookController();
          final scroll = ScrollController();
          addTearDown(controller.dispose);
          addTearDown(scroll.dispose);
          await _pump(tester, controller, scroll, scaler: scaler, dpr: dpr, width: width);

          final metrics = controller.renderer.activeRowMetrics!;
          final pitch = metrics.pitch;
          expect(pitch, (30 * scale).roundToDouble(), reason: 'pitch must follow the 16px body text');

          // Notebook: every heading fits one row, so the strut is forced.
          final field = tester.widget<TextField>(find.byType(TextField));
          expect(metrics.allHeadersFitOneRow, isTrue);
          expect(field.strutStyle!.forceStrutHeight, isTrue);
          // No double scaling: strut and style resolve to exactly one pitch.
          expect(field.strutStyle!.height! * scaler.scale(field.strutStyle!.fontSize!), closeTo(pitch, 1e-9));
          expect(field.style!.height! * scaler.scale(field.style!.fontSize!), closeTo(pitch, 1e-9));

          final painter = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((p) => p.painter)
              .whereType<RuledLinesPainter>()
              .single;
          expect(painter.fallbackLineHeight, pitch);
          expect(painter.devicePixelRatio, dpr);

          // The field's REAL layout: total height is exactly the ruled rows, and
          // probing the middle of every row lands on a distinct, increasing
          // visual line — a taller line anywhere would swallow a probe.
          final state = tester.state<EditableTextState>(find.byType(EditableText));
          final render = state.renderEditable;
          final ruled = painter.lineBottoms;
          for (var i = 0; i < ruled.length; i++) {
            expect(ruled[i], closeTo((i + 1) * pitch, 0.02), reason: 'row $i off the grid');
          }
          expect(render.size.height, closeTo(ruled.length * pitch, 0.02),
              reason: 'field height ${render.size.height} != ${ruled.length} rows of $pitch');
          final lineStarts = <int>[];
          for (var k = 0; k < ruled.length; k++) {
            final pos = render.getPositionForPoint(render.localToGlobal(Offset(1, (k + 0.5) * pitch)));
            lineStarts.add(pos.offset);
          }
          expect(lineStarts.toSet().length, ruled.length, reason: 'two rows resolved to one line: $lineStarts');
          expect([...lineStarts]..sort(), lineStarts);
          // Every line's caret sits inside its own row.
          for (var k = 0; k < ruled.length; k++) {
            final rect = render.getLocalRectForCaret(TextPosition(offset: lineStarts[k]));
            // The framework snaps caret rects to physical pixels (up to 1 px).
            expect(rect.top, greaterThanOrEqualTo(k * pitch - 1.0 / dpr));
            expect(rect.bottom, lessThanOrEqualTo((k + 1) * pitch + 1.0 / dpr));
          }
        });
      }
    }
  }

  // `RenderEditable` wraps 3px (1 + cursorWidth) narrower than its box. A line
  // whose width lands in that window stays on one row if measured at the full
  // width, while the field wraps it — every rule below it is then a row off.
  for (final scale in [1.0, 1.4]) {
    for (final heading in [false, true]) {
      testWidgets('a line wrapping inside the caret gap is measured like the field (heading: $heading, scale $scale)', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1000, 4000);
        addTearDown(tester.view.reset);
        const line = 'Hello wide world';
        final probe = TextPainter(
          text: TextSpan(
            text: line,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: heading ? 24 : 16,
              fontWeight: heading ? FontWeight.bold : FontWeight.normal,
              letterSpacing: 0.2,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout();
        final textWidth = probe.width;
        // Text area = textWidth + 1.5: fits when measured at the full width,
        // wraps in the field (which only has textWidth - 1.5 to use).
        final width = textWidth + 1.5 + 58 + 24;
        final controller = RichEditorController(
          text: line,
          theme: notebookTheme,
          initialAttributes: [
            if (heading) TextAttribute(start: 0, end: line.length, type: AttributeType.header, value: 'h1'),
          ],
        );
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        await _pump(tester, controller, scroll, scale: scale, dpr: 1.0, width: width);
        final pitch = controller.renderer.activeRowMetrics!.pitch;
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .whereType<RuledLinesPainter>()
            .single;
        final fieldRows = (tester.state<EditableTextState>(find.byType(EditableText)).renderEditable.size.height / pitch).round();
        expect(fieldRows, 2, reason: 'test setup: the field must wrap this line');
        expect(painter.lineBottoms.length, fieldRows, reason: 'ruled rows must equal the rows the field really lays out');
      });
    }
  }

  testWidgets('a theme whose headings need several rows keeps the multi-row path (strut not forced)', (tester) async {
    // The package default h1=28 over a 30px row needs two rows with Roboto.
    final controller = RichEditorController(
      text: 'Title\nbody',
      theme: const RichTextRenderTheme(lineHeight: 30),
      initialAttributes: const [TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1')],
    );
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await _pump(tester, controller, scroll, scale: 1.0, dpr: 1.0);
    final metrics = controller.renderer.activeRowMetrics!;
    expect(metrics.allHeadersFitOneRow, isFalse);
    expect(tester.widget<TextField>(find.byType(TextField)).strutStyle!.forceStrutHeight, isFalse);
  });
}
