// Enter on the empty last line of a code block leaves the block, so ordinary text
// can follow a block that ends the note; a blank line inside code stays a blank line.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

TextAttribute _code(int s, int e) => TextAttribute(start: s, end: e, type: AttributeType.header, value: 'code:dart');

String? _level(RichEditorController c, int i) => c.document.paragraphs.records[i].headerLevel;

void main() {
  RichEditorController make(String text, int codeEnd) => RichEditorController(text: text, initialAttributes: [_code(0, codeEnd)]);

  void enter(RichEditorController c) {
    final sel = c.selection;
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, '\n'),
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }

  test('Enter at the end of code adds a code line; Enter again on that empty line leaves the block', () {
    final c = make('a = 1', 5);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 5);
    enter(c);
    expect(c.text, 'a = 1\n');
    expect(_level(c, 1), 'code:dart', reason: 'the new line is still code');
    enter(c);
    expect(c.text, 'a = 1\n', reason: 'no third line: the second Enter converts the empty one');
    expect(_level(c, 0), 'code:dart');
    expect(_level(c, 1), isNull, reason: 'the empty last line is now an ordinary paragraph');
    expect(c.selection.baseOffset, 6);
    // and text typed there is normal text
    c.value = const TextEditingValue(text: 'a = 1\nhello', selection: TextSelection.collapsed(offset: 11));
    expect(_level(c, 1), isNull);
  });

  test('a carried indent does not keep the line in the block', () {
    final c = make('  x', 3);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 3);
    enter(c);
    expect(c.text, '  x\n  ', reason: 'the new line carries the indent');
    enter(c);
    expect(c.text, '  x\n', reason: 'the indent-only line is emptied when leaving');
    expect(_level(c, 1), isNull);
  });

  test('a blank line in the middle of code is still just a blank line', () {
    final c = make('a\n\nb', 4);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 2); // on the empty middle line
    enter(c);
    expect(c.text, 'a\n\n\nb');
    expect(_level(c, 1), 'code:dart');
    expect(_level(c, 2), 'code:dart');
  });

  test('leaving the block is one undo step', () {
    final c = make('a = 1', 5);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 5);
    enter(c);
    enter(c);
    c.undo();
    expect(_level(c, 1), 'code:dart');
    expect(c.text, 'a = 1\n');
  });

  test('programmatic Enter behaves the same', () {
    final c = make('a', 1);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 1);
    c.insertText('\n');
    c.insertText('\n');
    expect(c.text, 'a\n');
    expect(_level(c, 1), isNull);
  });
}
