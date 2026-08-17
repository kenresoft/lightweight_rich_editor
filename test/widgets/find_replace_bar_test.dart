import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/controller/rich_editor_controller.dart';
import 'package:lightweight_rich_editor/src/widgets/find_replace_bar.dart';

Future<void> _pumpBar(WidgetTester tester, RichEditorController controller, {VoidCallback? onClose}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: FindReplaceBar(controller: controller, onClose: onClose)),
  ));
}

void main() {
  testWidgets('typing a query searches and shows a match count', (tester) async {
    final controller = RichEditorController(text: 'the cat sat on the mat');
    await _pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'at');
    await tester.pump();

    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('next/previous buttons navigate matches', (tester) async {
    final controller = RichEditorController(text: 'cat cat cat');
    await _pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Next match'));
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous match'));
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('shows "No results" for a query with no matches', (tester) async {
    final controller = RichEditorController(text: 'hello world');
    await _pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'xyz');
    await tester.pump();

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('next/previous are disabled with no matches', (tester) async {
    final controller = RichEditorController(text: 'hello world');
    await _pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'xyz');
    await tester.pump();

    final nextButton = tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip('Next match'), matching: find.byType(IconButton)),
    );
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('expanding replace and tapping Replace All replaces every match', (tester) async {
    final controller = RichEditorController(text: 'cat cat cat');
    await _pumpBar(tester, controller);

    await tester.tap(find.byTooltip('Show replace'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(1), 'dog');
    await tester.pump();

    await tester.tap(find.text('Replace All'));
    await tester.pump();

    expect(controller.document.text, 'dog dog dog');
  });

  testWidgets('Replace replaces only the current match', (tester) async {
    final controller = RichEditorController(text: 'cat cat cat');
    await _pumpBar(tester, controller);

    await tester.tap(find.byTooltip('Show replace'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'dog');
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Replace'));
    await tester.pump();

    expect(controller.document.text, 'dog cat cat');
  });

  testWidgets('close button clears the search and calls onClose', (tester) async {
    final controller = RichEditorController(text: 'cat cat');
    var closed = false;
    await _pumpBar(tester, controller, onClose: () => closed = true);

    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    expect(controller.search.matchCount, 2);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(closed, isTrue);
    expect(controller.search.matchCount, 0);
  });

  testWidgets('case-sensitive toggle narrows results', (tester) async {
    final controller = RichEditorController(text: 'Cat cat CAT');
    await _pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.text('Aa'));
    await tester.pump();

    expect(find.text('1 of 1'), findsOneWidget);
  });

  testWidgets('disposing the bar clears the search', (tester) async {
    final controller = RichEditorController(text: 'cat cat');
    await _pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    expect(controller.search.matchCount, 2);

    await tester.pumpWidget(const SizedBox()); // unmounts FindReplaceBar

    expect(controller.search.matchCount, 0);
  });

  testWidgets('Escape closes the bar and clears the search', (tester) async {
    final controller = RichEditorController(text: 'cat cat');
    var closed = false;
    await _pumpBar(tester, controller, onClose: () => closed = true);

    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    expect(controller.search.matchCount, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closed, isTrue);
    expect(controller.search.matchCount, 0);
  });

  testWidgets('Shift+Enter in the query field navigates to the previous match', (tester) async {
    final controller = RichEditorController(text: 'cat cat cat');
    await _pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(find.text('3 of 3'), findsOneWidget);
  });
}