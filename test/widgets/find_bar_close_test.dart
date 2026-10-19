import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  testWidgets('removing the find bar does not notify during the frame', (tester) async {
    final controller = RichEditorController(text: 'one two one');
    addTearDown(controller.dispose);
    var show = true;
    late StateSetter set;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return Column(
                children: [
                  if (show) FindReplaceBar(controller: controller),
                  Expanded(
                    child: RichTextEditor(
                      controller: controller,
                      scrollController: ScrollController(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'one');
    await tester.pumpAndSettle();

    set(() => show = false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
