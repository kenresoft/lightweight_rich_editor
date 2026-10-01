// Editing inside a code block: Enter keeps the indentation, Tab / Shift+Tab
// indent and outdent (one undo step), Backspace and merges leave the block and
// its text intact, language changes never touch the text.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

RichEditorController make(String text, {int? codeEnd, int codeStart = 0}) => RichEditorController(
      text: text,
      theme: notebookTheme,
      initialAttributes: [
        if (codeEnd != null) TextAttribute(start: codeStart, end: codeEnd, type: AttributeType.header, value: 'code'),
      ],
    );

List<String?> levels(RichEditorController c) => c.document.paragraphs.records.map((r) => r.headerLevel).toList();

void type(RichEditorController c, String text, int caret) =>
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Enter', () {
    test('keeps the indentation of the line the caret is on', () {
      final c = make('  if (x) {', codeEnd: 10);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 10);
      type(c, '  if (x) {\n', 11); // what the IME reports for Enter
      expect(c.document.text, '  if (x) {\n  ');
      expect(c.selection, const TextSelection.collapsed(offset: 13), reason: 'caret after the carried indent');
      expect(levels(c), ['code', 'code']);
    });

    test('mid-indent: only the whitespace before the caret is carried', () {
      final c = make('    x', codeEnd: 5);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 2);
      type(c, '  \n  x', 3);
      expect(c.document.text, '  \n    x');
      expect(levels(c), ['code', 'code']);
    });

    test('a tab indent is carried as a tab', () {
      final c = make('\tfoo', codeEnd: 4);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 4);
      type(c, '\tfoo\n', 5);
      expect(c.document.text, '\tfoo\n\t');
    });

    test('no indentation, no extra characters — and prose is unaffected', () {
      final c = make('  prose\ncode', codeStart: 8, codeEnd: 12);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 7);
      type(c, '  prose\n\ncode', 8);
      expect(c.document.text, '  prose\n\ncode', reason: 'indentation is carried only inside code');
    });

    test('undo removes the new line and its indent together', () {
      final c = make('  a', codeEnd: 3);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 3);
      type(c, '  a\n', 4);
      expect(c.document.text, '  a\n  ');
      c.undo();
      expect(c.document.text, '  a');
      expect(levels(c), ['code']);
    });
  });

  group('Tab / Shift+Tab', () {
    test('Tab with a caret inserts two spaces at the caret', () {
      final c = make('ab', codeEnd: 2);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 1);
      c.indentCode();
      expect(c.document.text, 'a  b');
      expect(c.selection, const TextSelection.collapsed(offset: 3));
    });

    test('Tab on a selection indents every selected non-empty line, keeps the selection, is one undo step', () {
      final c = make('a\n\nb\nc', codeEnd: 6);
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 4); // a, blank, b
      c.indentCode();
      expect(c.document.text, '  a\n\n  b\nc', reason: 'blank line left blank; line c not selected');
      expect(c.selection.start, 0);
      expect(c.selection.end, 8);
      expect(levels(c), ['code', 'code', 'code', 'code']);
      c.undo();
      expect(c.document.text, 'a\n\nb\nc');
      expect(levels(c), ['code', 'code', 'code', 'code']);
      c.redo();
      expect(c.document.text, '  a\n\n  b\nc');
    });

    test('a selection that ends at the start of the next line does not indent that line', () {
      final c = make('a\nb', codeEnd: 3);
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
      c.indentCode();
      expect(c.document.text, '  a\nb');
    });

    test('Shift+Tab removes up to two leading spaces from the caret line', () {
      final c = make('    deep\n  mid\n x', codeEnd: 16);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 6);
      c.outdentCode();
      expect(c.document.text, '  deep\n  mid\n x');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });

    test('Shift+Tab on selected lines: two spaces, one space, a tab, or nothing', () {
      final c = make('  a\n b\n\tc\nd', codeEnd: 11);
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 11);
      c.outdentCode();
      expect(c.document.text, 'a\nb\nc\nd');
      c.outdentCode();
      expect(c.document.text, 'a\nb\nc\nd', reason: 'nothing left to remove is a no-op, not an error');
    });

    test('outside a code block Tab and Shift+Tab do nothing', () {
      final c = make('plain text');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 3);
      c.indentCode();
      c.outdentCode();
      expect(c.document.text, 'plain text');
    });
  });

  group('Backspace, merge, split', () {
    test('Backspace through indentation removes one space at a time and keeps the block', () {
      final c = make('    x', codeEnd: 5);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 4);
      type(c, '   x', 3);
      expect(c.document.text, '   x');
      expect(levels(c), ['code']);
    });

    test('joining two code lines keeps one code line with both texts', () {
      final c = make('ab\ncd', codeEnd: 5);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 3);
      type(c, 'abcd', 2);
      expect(c.document.text, 'abcd');
      expect(levels(c), ['code']);
    });

    test('deleting a blank code line inside a block keeps the block contiguous', () {
      final c = make('a\n\nb', codeEnd: 4);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 2);
      type(c, 'a\nb', 1);
      expect(levels(c), ['code', 'code']);
    });

    test('deleting the whole block leaves the surrounding prose intact', () {
      final c = make('before\ncode\nafter', codeStart: 7, codeEnd: 11);
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 7, extentOffset: 12);
      c.value = const TextEditingValue(text: 'before\nafter', selection: TextSelection.collapsed(offset: 7));
      expect(c.document.text, 'before\nafter');
      expect(levels(c), [null, null]);
    });

    test('splitting a code line in the middle gives two code lines', () {
      final c = make('abcd', codeEnd: 4);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 2);
      type(c, 'ab\ncd', 3);
      expect(c.document.text, 'ab\ncd');
      expect(levels(c), ['code', 'code']);
    });
  });

  group('toggle and language', () {
    test('toggling the block off and on keeps every character, blank lines and indentation', () {
      const text = 'void f() {\n\n  go();\n}';
      final c = make(text, codeEnd: text.length);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 2);
      c.toggleCodeBlock();
      expect(c.document.text, text);
      expect(levels(c), [null, null, null, null]);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: text.length);
      c.toggleCodeBlock();
      expect(c.document.text, text);
      expect(levels(c), ['code', 'code', 'code', 'code']);
    });

    test('changing the language leaves the code untouched', () {
      const text = '  a\n\n b';
      final c = make(text, codeEnd: text.length);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 1);
      c.setCodeBlockLanguage('dart');
      c.setCodeBlockLanguage('python');
      c.setCodeBlockLanguage(null);
      expect(c.document.text, text);
    });

    test('Tab on a prose or list line is not captured by the code handler', () {
      final c = make('- item');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 4);
      expect(c.isCodeBlockActive, isFalse);
    });
  });

  group('mounted: Tab key', () {
    testWidgets('Tab in a code block indents; it does not move focus out of the editor', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 900);
      addTearDown(tester.view.reset);
      final c = make('ab', codeEnd: 2);
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Expanded(child: RichTextEditor(controller: c, scrollController: ScrollController())),
            const TextField(key: ValueKey('other')),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      c.focusNode.requestFocus();
      await tester.pumpAndSettle();
      c.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(c.document.text, '  ab');
      expect(c.focusNode.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(c.document.text, 'ab');
      expect(c.focusNode.hasFocus, isTrue);
    });
  });
}
