// Enter on an empty list item ends the list: the item becomes an empty paragraph
// and the caret stays on it (no stray blank row after the list).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RichEditorController at(String text) =>
      RichEditorController(text: text)..selection = TextSelection.collapsed(offset: text.length);

  test('bullet list: Enter continues it, Enter again ends it on the same row', () {
    final c = at('- a');
    addTearDown(c.dispose);
    c.insertText('\n');
    expect(c.document.text, '- a\n- ');
    c.insertText('\n');
    expect(c.document.text, '- a\n');
    expect(c.selection, const TextSelection.collapsed(offset: 4));
  });

  test('numbered list the same, and typing afterwards is plain text', () {
    final c = at('1. one');
    addTearDown(c.dispose);
    c.insertText('\n');
    expect(c.document.text, '1. one\n2. ');
    c.insertText('\n');
    expect(c.document.text, '1. one\n');
    c.insertText('after');
    expect(c.document.text, '1. one\nafter');
  });

  test('checklist the same', () {
    final c = at('- [ ] task');
    addTearDown(c.dispose);
    c.insertText('\n');
    expect(c.document.text, '- [ ] task\n- [ ] ');
    c.insertText('\n');
    expect(c.document.text, '- [ ] task\n');
  });

  test('ending an empty item in the middle of a numbered list leaves the others alone', () {
    final c = RichEditorController(text: '1. a\n2. \n3. b');
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 8);
    c.insertText('\n');
    expect(c.document.text, '1. a\n\n3. b');
  });

  test('undo brings the empty item back', () {
    final c = at('- a');
    addTearDown(c.dispose);
    c.insertText('\n');
    c.insertText('\n');
    c.undo();
    expect(c.document.text, '- a\n- ');
  });
}
