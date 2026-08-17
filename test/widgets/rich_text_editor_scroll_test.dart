import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/controller/rich_editor_controller.dart';
import 'package:lightweight_rich_editor/src/widgets/rich_text_editor.dart';

void main() {
  group('RichTextEditor — scroll to current search match', () {
    testWidgets('scrolls an off-screen match into view after find', (tester) async {
      final lines = List.generate(60, (i) => i == 55 ? 'TARGET line' : 'Line $i');
      final controller = RichEditorController(text: lines.join('\n'));
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: RichTextEditor(controller: controller, scrollController: scrollController),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // autofocus + no explicit initial selection normalizes the caret
      // to the end of the text and scrolls there on its own -- pin a
      // known starting point before measuring find()'s own effect.
      // Setting `.selection` alone doesn't move the viewport back
      // (unsurprising -- that's the exact gap this feature closes for
      // search matches), so reset the scroll position directly.
      scrollController.jumpTo(0);
      await tester.pumpAndSettle();
      expect(scrollController.offset, 0);

      controller.find('TARGET');
      await tester.pumpAndSettle();

      expect(scrollController.offset, greaterThan(0));
    });

    testWidgets('does not scroll when the match is already visible', (tester) async {
      final controller = RichEditorController(text: 'TARGET at the very top\nsecond line');
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: RichTextEditor(controller: controller, scrollController: scrollController),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.find('TARGET');
      await tester.pumpAndSettle();

      expect(scrollController.offset, 0);
    });

    testWidgets('findNext scrolls to the next off-screen match', (tester) async {
      final lines = List.generate(60, (i) {
        if (i == 0) return 'TARGET line';
        if (i == 55) return 'TARGET line';
        return 'Line $i';
      });
      final controller = RichEditorController(text: lines.join('\n'));
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: RichTextEditor(controller: controller, scrollController: scrollController),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scrollController.jumpTo(0);
      await tester.pumpAndSettle();

      controller.find('TARGET');
      await tester.pumpAndSettle();
      expect(scrollController.offset, 0); // first match is already visible

      controller.findNext();
      await tester.pumpAndSettle();

      expect(scrollController.offset, greaterThan(0));
    });
  });
}
