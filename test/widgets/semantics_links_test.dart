import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  testWidgets('links and checklists mount with semantics on', (tester) async {
    final handle = tester.ensureSemantics();
    final parsed = const MarkdownImporter().parse(
      '- [ ] pack\n\nSee [guide](https://example.com/guide).',
    );
    final controller = RichEditorController(
      text: parsed.text,
      initialAttributes: parsed.attributes,
      interactiveLinks: true,
    );
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichTextEditor(controller: controller, scrollController: scroll),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
