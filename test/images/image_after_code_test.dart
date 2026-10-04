// A picture put in at the end of a code line (or a heading) leaves an ordinary line after it,
// where the caret goes: typing there is normal text, not one more line of the block.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

String? _levelAt(RichEditorController c, int offset) => c.document.paragraphs.paragraphAt(offset)?.headerLevel;

void main() {
  RichEditorController block(String text, {String? level}) {
    final c = RichEditorController(text: text, theme: notebookTheme);
    c.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    if (level == 'code') {
      c.toggleCodeBlock();
    } else if (level != null) {
      c.setHeader(level);
    }
    c.selection = TextSelection.collapsed(offset: text.length);
    return c;
  }

  test('end of a code line: the line after the picture is not code', () {
    final c = block('print(1)', level: 'code');
    addTearDown(c.dispose);
    c.insertImageBlock('pic', rows: 4);
    expect(_levelAt(c, c.selection.baseOffset), isNull);
    c.insertText('hello');
    expect(c.document.paragraphs.paragraphAt(c.selection.baseOffset)?.headerLevel, isNull);
    expect(c.text.endsWith('hello'), isTrue);
  });

  test('empty code line used for the picture: same', () {
    final c = block('print(1)', level: 'code');
    addTearDown(c.dispose);
    c.insertText('\n');
    c.insertImageBlock('pic', rows: 4);
    expect(_levelAt(c, c.selection.baseOffset), isNull);
  });

  test('middle of a code line: the rest of the line stays code', () {
    final c = block('print(1)', level: 'code');
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 5);
    c.insertImageBlock('pic', rows: 4);
    expect(c.text.substring(c.selection.baseOffset), '(1)');
    expect(isCodeBlockLevel(_levelAt(c, c.selection.baseOffset)), isTrue);
  });

  test('end of a heading: the line after the picture is plain', () {
    final c = block('Title', level: 'h1');
    addTearDown(c.dispose);
    c.insertImageBlock('pic', rows: 4);
    expect(_levelAt(c, c.selection.baseOffset), isNull);
  });

  test('one undo step takes the picture and the line change away', () {
    final c = block('print(1)', level: 'code');
    addTearDown(c.dispose);
    c.insertImageBlock('pic', rows: 4);
    c.undo();
    expect(c.text, 'print(1)');
    expect(isCodeBlockLevel(_levelAt(c, 0)), isTrue);
  });
}
