// Switching between reading and editing a note that holds a code block raises no error.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

void main() {
  testWidgets('toggle read-only back and forth with a code block', (tester) async {
    final c = RichEditorController(text: 'hello\nprint(1)\nmore text here', theme: notebookTheme);
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 14);
    c.toggleCodeBlock();
    c.selection = const TextSelection.collapsed(offset: 0);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final readOnly = ValueNotifier<bool>(false);
    addTearDown(readOnly.dispose);

    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      if (errors.isEmpty) debugPrint('FIRST: ${d.exception} ${d.stack}');
      errors.add(d);
      previous?.call(d);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: readOnly,
            builder: (_, ro, _) => SizedBox(
              height: 400,
              child: RichTextEditor(controller: c, scrollController: scroll, readOnly: ro),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      readOnly.value = !readOnly.value;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tapAt(const Offset(120, 90));
    await tester.pump();

    if (errors.isNotEmpty) {
      debugPrint('FIRST: ${errors.first.exception}\n${errors.first.stack}');
    }
    expect(errors, isEmpty);
  });
}
