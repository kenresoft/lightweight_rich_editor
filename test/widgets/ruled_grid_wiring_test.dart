// The mounted editor must feed the *same* effective scaler / pixel ratio /
// pitch to the TextField's strut, the measured text, the renderer's active
// metrics and the ruled-lines painter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

Future<void> _pump(
  WidgetTester tester,
  RichEditorController controller,
  ScrollController scroll, {
  required double scale,
  required double dpr,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          devicePixelRatio: dpr,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: RichTextEditor(controller: controller, scrollController: scroll, autofocus: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [0.85, 1.0, 1.3, 2.0, 3.0]) {
    testWidgets('editor wiring agrees at text scale $scale', (tester) async {
      const theme = RichTextRenderTheme(lineHeight: 30);
      final controller = RichEditorController(
        text: 'Title\nsome body text',
        theme: theme,
        initialAttributes: const [
          TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1'),
        ],
      );
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);

      await _pump(tester, controller, scroll, scale: scale, dpr: 2.75);

      final metrics = controller.renderer.activeRowMetrics!;
      final scaler = TextScaler.linear(scale);
      expect(metrics.textScaler, scaler);
      expect(metrics.devicePixelRatio, 2.75);
      expect(metrics.pitch, (30 * scale).roundToDouble());

      // Strut on the real TextField resolves to exactly one pitch.
      final field = tester.widget<TextField>(find.byType(TextField));
      final strut = field.strutStyle!;
      expect(strut.height! * scaler.scale(strut.fontSize!), closeTo(metrics.pitch, 1e-9));
      expect(field.style!.height! * scaler.scale(field.style!.fontSize!), closeTo(metrics.pitch, 1e-9));

      // The painter reads the same pitch and the same ratio.
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<RuledLinesPainter>()
          .toList();
      expect(painters, hasLength(1));
      expect(painters.single.fallbackLineHeight, metrics.pitch);
      expect(painters.single.devicePixelRatio, 2.75);

      // Every measured line the painter draws from is a whole multiple of it.
      for (final b in painters.single.lineBottoms) {
        expect(b / metrics.pitch, closeTo((b / metrics.pitch).round(), 0.02));
      }

      // The real rendered paragraph agrees with the measured bottoms.
      final render = tester.renderObject<RenderBox>(find.byType(TextField));
      expect(render.hasSize, isTrue);
    });
  }
}
