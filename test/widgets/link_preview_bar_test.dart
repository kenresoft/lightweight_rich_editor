import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/controller/rich_editor_controller.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';
import 'package:lightweight_rich_editor/src/utils/link_launcher.dart';
import 'package:lightweight_rich_editor/src/utils/url_detector.dart';
import 'package:lightweight_rich_editor/src/widgets/link_edit_sheet.dart';
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

  testWidgets('typing or pasting next to a link does not pop the bar; moving the caret onto it does', (tester) async {
    final c = linked();
    await mount(tester, c, autofocus: true);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    expect(find.byType(LinkPreviewBar), findsOneWidget);
    // an edit that leaves the caret inside the link
    c.value = TextEditingValue(text: 'Click hexre for docs', selection: const TextSelection.collapsed(offset: 9));
    await tester.pump();
    expect(find.byType(LinkPreviewBar), findsNothing);
    // moving away and back is a deliberate touch
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 0));
    await tester.pump();
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    expect(find.byType(LinkPreviewBar), findsOneWidget);
  });

  testWidgets('Remove link unlinks and keeps the text, as one undo step', (tester) async {
    final c = linked();
    await mount(tester, c, autofocus: true);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove link'));
    await tester.pump();
    expect(c.linkUrlAt(8), isNull);
    expect(c.document.text, 'Click here for docs');
    expect(find.byType(LinkPreviewBar), findsNothing);
    c.undo();
    expect(c.linkUrlAt(8), 'https://docs.example.com/cms/');
  });

  testWidgets('Edit link: change the text and the address in a sheet', (tester) async {
    final c = linked();
    await mount(tester, c, autofocus: true);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit link'));
    await tester.pumpAndSettle();
    expect(find.text('Edit link'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Text'), 'our docs');
    await tester.enterText(find.widgetWithText(TextField, 'Link'), 'kenresoft.com/docs');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.document.text, 'Click our docs for docs');
    expect(c.linkUrlAt(8), 'https://kenresoft.com/docs');
    expect(c.linkRangeAt(8), const TextRange(start: 6, end: 14));
    c.undo();
    expect(c.document.text, 'Click here for docs');
    expect(c.linkUrlAt(8), 'https://docs.example.com/cms/');
  });

  testWidgets('Edit link: an email address is stored as mail, an unopenable one is refused', (tester) async {
    final c = linked();
    await mount(tester, c, autofocus: true);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Link'), 'javascript:alert(1)');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text("That isn't a link we can open"), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Link'), 'kix@gmail.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.linkUrlAt(8), 'mailto:kix@gmail.com');
  });

  testWidgets('Edit sheet: Remove link', (tester) async {
    final c = linked();
    await mount(tester, c, autofocus: true);
    c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove link'));
    await tester.pumpAndSettle();
    expect(c.linkUrlAt(8), isNull);
    expect(c.document.text, 'Click here for docs');
  });

  test('an address autolinks as mail, never as https://name@host', () {
    expect(normalizeUrlToken('kix@gmail.com'), 'mailto:kix@gmail.com');
    expect(normalizeUrlToken('first.last+tag@sub.example.co.uk'), 'mailto:first.last+tag@sub.example.co.uk');
    expect(normalizeUrlToken('example.com'), 'https://example.com');
    // telephone numbers: international, national with a leading 0, 3-3-4
    expect(normalizeUrlToken('+2348012345678'), 'tel:+2348012345678');
    expect(normalizeUrlToken('+1-800-555-0199'), 'tel:+18005550199');
    expect(normalizeUrlToken('08012345678'), 'tel:08012345678');
    expect(normalizeUrlToken('800-555-0199'), 'tel:8005550199');
    expect(detectAllUrls('call +2348012345678 now').single.href, 'tel:+2348012345678');
    // plain numbers are not phones
    expect(normalizeUrlToken('12345678'), isNull);
    expect(normalizeUrlToken('2026'), isNull);
    expect(normalizeUrlToken('1,500.00'), isNull);
    expect(detectAllUrls('write kix@gmail.com now').single.href, 'mailto:kix@gmail.com');
    // links stored wrongly by an older build still open as mail
    expect(normalizeLinkUri('https://kix@gmail.com')?.toString(), 'mailto:kix@gmail.com');
    expect(normalizeLinkUri('https://user:pw@host.com/x')?.scheme, 'https');
    expect(linkDisplayTarget('https://kix@gmail.com'), 'kix@gmail.com');
    expect(hrefForInput('kix@gmail.com'), 'mailto:kix@gmail.com');
    expect(hrefForInput('kenresoft.com/x'), 'https://kenresoft.com/x');
    expect(hrefForInput('tel:+2348012345678'), 'tel:+2348012345678');
    expect(hrefForInput('javascript:alert(1)'), isNull);
  });

  test('the bar splits a URL into host and the rest', () {
    expect(LinkPreviewBar.split('https://www.kenresoft.com/cms/?a=1'), ('kenresoft.com', '/cms/?a=1'));
    expect(LinkPreviewBar.split('https://kenresoft.com/'), ('kenresoft.com', ''));
    expect(LinkPreviewBar.split('not a url'), ('not a url', ''));
  });
}
