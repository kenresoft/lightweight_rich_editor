// Enter at the end of a code block: the first Enter adds a code line, the next one on that
// empty line leaves the block, wherever the block sits in the note.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Types Enter the way the keyboard does: the field's value changes by one '\n'.
  void enter(RichEditorController c) {
    final sel = c.selection;
    final t = c.text;
    c.value = TextEditingValue(
      text: t.replaceRange(sel.start, sel.end, '\n'),
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }

  RichEditorController codeAt(String text, {required int caret}) {
    final c = RichEditorController(text: text);
    c.selection = TextSelection.collapsed(offset: caret);
    c.toggleCodeBlock();
    c.selection = TextSelection.collapsed(offset: caret);
    return c;
  }

  test('block at the end of the note: Enter, Enter leaves it', () {
    final c = codeAt('print(1)', caret: 8);
    addTearDown(c.dispose);
    enter(c);
    expect(c.isCodeBlockActive, isTrue);
    enter(c);
    expect(c.isCodeBlockActive, isFalse);
    expect(c.text, 'print(1)\n');
    c.value = TextEditingValue(text: '${c.text}x', selection: TextSelection.collapsed(offset: c.text.length + 1));
    expect(c.isCodeBlockActive, isFalse);
  });

  test('block followed by a normal line: Enter, Enter leaves it', () {
    final c = codeAt('print(1)\nafter', caret: 8);
    addTearDown(c.dispose);
    enter(c);
    expect(c.text, 'print(1)\n\nafter');
    enter(c);
    expect(c.isCodeBlockActive, isFalse);
    expect(c.text, 'print(1)\n\nafter');
  });

  test('block after a normal line', () {
    final c = RichEditorController(text: 'intro\nprint(1)');
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 14);
    c.toggleCodeBlock();
    c.selection = const TextSelection.collapsed(offset: 14);
    enter(c);
    enter(c);
    expect(c.isCodeBlockActive, isFalse);
  });

  test('three Enters never grow the block by more than one empty line', () {
    final c = codeAt('a', caret: 1);
    addTearDown(c.dispose);
    enter(c);
    enter(c);
    enter(c);
    expect(c.text.split('\n').length, lessThanOrEqualTo(4));
    expect(c.isCodeBlockActive, isFalse);
  });
}
