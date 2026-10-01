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
      expect(find.textContaining('example.com'), findsOneWidget);

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
  RichEditorController linked() => RichEditorController(
        text: 'Click here for docs',
        initialAttributes: [TextAttribute(start: 6, end: 10, type: AttributeType.link, value: 'https://docs.example.com/cms/')],
      );

  Future<void> mount(WidgetTester tester, RichEditorController c, {required bool autofocus}) async {
    final sc = ScrollController();
    addTearDown(sc.dispose);
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(height: 300, child: RichTextEditor(controller: c, scrollController: sc, autofocus: autofocus)),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a note that opens with its caret inside a link, without focus, shows no bar', (tester) async {
    final c = linked();
    await mount(tester, c, autofocus: false);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    expect(find.byType(LinkPreviewBar), findsNothing);
    // the user taps into the editor: now it is shown
    c.focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(find.byType(LinkPreviewBar), findsOneWidget);
  });

  testWidgets('Dismiss hides the bar until the caret moves into a link again', (tester) async {
    final c = linked();
    await mount(tester, c, autofocus: true);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    expect(find.byType(LinkPreviewBar), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.byType(LinkPreviewBar), findsNothing);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 0));
    await tester.pump();
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 9));
    await tester.pump();
    expect(find.byType(LinkPreviewBar), findsOneWidget);
  });

  test('the bar splits a URL into host and the rest', () {
    expect(LinkPreviewBar.split('https://www.kenresoft.com/cms/?a=1'), ('kenresoft.com', '/cms/?a=1'));
    expect(LinkPreviewBar.split('https://kenresoft.com/'), ('kenresoft.com', ''));
    expect(LinkPreviewBar.split('not a url'), ('not a url', ''));
  });
}
