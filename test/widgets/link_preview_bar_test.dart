import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/controller/rich_editor_controller.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';
import 'package:lightweight_rich_editor/src/widgets/link_preview_bar.dart';
import 'package:lightweight_rich_editor/src/widgets/rich_text_editor.dart';

void main() {
  testWidgets(
    'the link preview bar appears when the caret is inside a link and '
    'disappears once it moves away',
    (tester) async {
      const text = 'Click here for docs';
      final linkStart = text.indexOf('here');
      final linkEnd = linkStart + 'here'.length;
      final controller = RichEditorController(
        text: text,
        initialAttributes: [
          TextAttribute(start: linkStart, end: linkEnd, type: AttributeType.link, value: 'https://example.com'),
        ],
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: RichTextEditor(controller: controller, scrollController: scrollController),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(LinkPreviewBar), findsNothing);

      controller.value = controller.value.copyWith(
        selection: TextSelection.collapsed(offset: linkStart + 1),
      );
      await tester.pump();

      expect(find.byType(LinkPreviewBar), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);

      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 0),
      );
      await tester.pump();

      expect(find.byType(LinkPreviewBar), findsNothing);
    },
  );

  testWidgets('does not appear for a real (non-collapsed) selection, even one touching a link', (tester) async {
    const text = 'Click here for docs';
    final linkStart = text.indexOf('here');
    final linkEnd = linkStart + 'here'.length;
    final controller = RichEditorController(
      text: text,
      initialAttributes: [
        TextAttribute(start: linkStart, end: linkEnd, type: AttributeType.link, value: 'https://example.com'),
      ],
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: RichTextEditor(controller: controller, scrollController: scrollController),
        ),
      ),
    ));

    controller.value = controller.value.copyWith(
      selection: TextSelection(baseOffset: linkStart, extentOffset: linkEnd),
    );
    await tester.pump();

    expect(find.byType(LinkPreviewBar), findsNothing);
  });
}
