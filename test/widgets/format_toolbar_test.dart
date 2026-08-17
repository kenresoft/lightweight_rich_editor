import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/controller/rich_editor_controller.dart';
import 'package:lightweight_rich_editor/src/painters/ruled_lines_painter.dart';
import 'package:lightweight_rich_editor/src/widgets/format_toolbar.dart';

Future<void> _pumpToolbar(WidgetTester tester, RichEditorController controller) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FormatToolbar(
        controller: controller,
        showMargin: true,
        onToggleMargin: () {},
        lineStyle: RuledLineStyle.solid,
        onToggleLineStyle: () {},
        onSave: () {},
        onLoad: () {},
      ),
    ),
  ));
}

void main() {
  group('FormatToolbar — font size indicator', () {
    testWidgets('shows the theme base font size by default', (tester) async {
      final controller = RichEditorController(text: 'hello world');
      await _pumpToolbar(tester, controller);

      expect(find.text('${controller.renderer.theme.baseFontSize.round()}'), findsOneWidget);
    });

    testWidgets('updates live after increaseFontSize is called at the caret', (tester) async {
      final controller = RichEditorController(text: 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 3);
      await _pumpToolbar(tester, controller);

      final before = controller.renderer.theme.baseFontSize.round();
      expect(find.text('$before'), findsOneWidget);

      controller.increaseFontSize();
      await tester.pump();

      expect(find.text('$before'), findsNothing);
      expect(find.text('${before + 2}'), findsOneWidget);
    });

    testWidgets('decreasing then increasing returns to the original displayed size', (tester) async {
      final controller = RichEditorController(text: 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 3);
      await _pumpToolbar(tester, controller);

      final original = controller.renderer.theme.baseFontSize.round();

      controller.decreaseFontSize();
      await tester.pump();
      expect(find.text('${original - 2}'), findsOneWidget);

      controller.increaseFontSize();
      await tester.pump();
      expect(find.text('$original'), findsOneWidget);
    });
  });

  group('FormatToolbar — heading indicator', () {
    testWidgets('shows the paragraph mark when no heading is active', (tester) async {
      final controller = RichEditorController(text: 'plain text');
      await _pumpToolbar(tester, controller);

      expect(find.text('¶'), findsOneWidget);
      expect(find.text('H1'), findsNothing);
      expect(find.text('H2'), findsNothing);
    });

    testWidgets('shows H1 once setHeader(h1) is applied at the caret', (tester) async {
      final controller = RichEditorController(text: 'a heading');
      controller.selection = const TextSelection.collapsed(offset: 2);
      await _pumpToolbar(tester, controller);

      controller.setHeader('h1');
      await tester.pump();

      expect(find.text('H1'), findsOneWidget);
      expect(find.text('¶'), findsNothing);
    });

    testWidgets('shows H2 once setHeader(h2) is applied at the caret', (tester) async {
      final controller = RichEditorController(text: 'a heading');
      controller.selection = const TextSelection.collapsed(offset: 2);
      await _pumpToolbar(tester, controller);

      controller.setHeader('h2');
      await tester.pump();

      expect(find.text('H2'), findsOneWidget);
    });

    testWidgets('reverts to the paragraph mark after clearing the heading', (tester) async {
      final controller = RichEditorController(text: 'a heading');
      controller.selection = const TextSelection.collapsed(offset: 2);
      await _pumpToolbar(tester, controller);

      controller.setHeader('h1');
      await tester.pump();
      expect(find.text('H1'), findsOneWidget);

      controller.setHeader(null);
      await tester.pump();
      expect(find.text('¶'), findsOneWidget);
      expect(find.text('H1'), findsNothing);
    });
  });

  group('FormatToolbar — color swatch indicator', () {
    Container swatchOf(WidgetTester tester) {
      return tester.widgetList<Container>(find.byType(Container)).firstWhere((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration && decoration.borderRadius == BorderRadius.circular(1.5);
      });
    }

    testWidgets('shows a transparent swatch when no color is applied', (tester) async {
      final controller = RichEditorController(text: 'hello world');
      await _pumpToolbar(tester, controller);

      final decoration = swatchOf(tester).decoration as BoxDecoration;
      expect(decoration.color, Colors.transparent);
    });

    testWidgets('shows the applied color once setColor is called at the caret', (tester) async {
      final controller = RichEditorController(text: 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 3);
      await _pumpToolbar(tester, controller);

      controller.setColor(const Color(0xFFFF0000).toARGB32());
      await tester.pump();

      final decoration = swatchOf(tester).decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFFF0000));
    });
  });
}
