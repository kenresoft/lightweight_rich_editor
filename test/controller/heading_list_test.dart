// A line that becomes a list item stops being a heading; the checklist marker never gains
// spaces by being typed over, deleted and retyped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

String levels(RichEditorController c) => c.document.paragraphs.records.map((r) => '${r.headerLevel}').join(',');

void main() {
  everyListKind();
  TestWidgetsFlutterBinding.ensureInitialized();

  RichEditorController heading(String text, {int caret = 0}) {
    final c = RichEditorController(text: text);
    addTearDown(c.dispose);
    c.selection = TextSelection.collapsed(offset: caret);
    c.setHeader('h1');
    return c;
  }

  test('a heading line made into a checklist item is no longer a heading', () {
    final c = heading('Title\nbody');
    c.toggleTaskItem();
    expect(c.document.text, '  - [ ] Title\nbody');
    expect(levels(c), 'null,null');
  });

  test('the same for bullets and numbers', () {
    final bullet = heading('Title');
    bullet.toggleBulletList();
    expect(levels(bullet), 'null');
    final numbered = heading('Title');
    numbered.toggleNumberedList();
    expect(levels(numbered), 'null');
  });

  test('an emptied heading line becomes a plain checklist line, and so does the next item after Enter', () {
    final c = heading('Title', caret: 5);
    for (var i = 0; i < 5; i++) {
      c.deleteBackward();
    }
    c.toggleTaskItem();
    c.insertText('first');
    c.insertText('\n');
    c.insertText('second');
    expect(c.document.text, '  - [ ] first\n  - [ ] second');
    expect(levels(c), 'null,null');
  });

  test('undo brings the heading and the plain line back together', () {
    final c = heading('Title');
    c.toggleTaskItem();
    c.undo();
    expect(c.document.text, 'Title');
    expect(levels(c), 'h1');
    c.redo();
    expect(c.document.text, '  - [ ] Title');
    expect(levels(c), 'null');
  });

  test('turning a list off leaves the line plain, and a code block is not touched by it', () {
    final c = heading('Title');
    c.toggleBulletList();
    c.toggleBulletList();
    expect(c.document.text, 'Title');
    expect(levels(c), 'null');
  });

  test('only the lines that become items lose their heading', () {
    final c = RichEditorController(text: 'One\nTwo\nThree');
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 0);
    c.setHeader('h1');
    c.selection = const TextSelection.collapsed(offset: 8);
    c.setHeader('h2');
    c.selection = const TextSelection.collapsed(offset: 5);
    c.toggleBulletList();
    expect(levels(c), 'h1,null,h2');
  });

  group('the checklist marker', () {
    test('deleting the text and typing again leaves the same marker', () {
      final c = RichEditorController(text: '');
      addTearDown(c.dispose);
      c.toggleTaskItem();
      final marker = c.document.text;
      for (var round = 0; round < 6; round++) {
        c.insertText('hello world');
        for (var i = 0; i < 'hello world'.length; i++) {
          c.deleteBackward();
        }
        expect(c.document.text, marker, reason: 'round $round');
      }
    });

    test('checking and unchecking never adds spaces', () {
      final c = RichEditorController(text: 'buy milk');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 3);
      c.toggleTaskItem();
      final first = c.document.text;
      for (var i = 0; i < 6; i++) {
        c.toggleTaskItem();
      }
      expect(c.document.text, first);
    });
  });
}

// The same rule for every kind of list, every way into it, and the line after it.
void everyListKind() {
  group('every kind of list', () {
    final kinds = <String, (void Function(RichEditorController), String)>{
      'bullet': ((c) => c.toggleBulletList(), '  - '),
      'numbered': ((c) => c.toggleNumberedList(), '  1. '),
      'checklist': ((c) => c.toggleTaskItem(), '  - [ ] '),
    };

    for (final entry in kinds.entries) {
      final name = entry.key;
      final (apply, marker) = entry.value;

      test('$name: a heading line becomes a plain list item, and so does every item after Enter', () {
        final c = RichEditorController(text: 'Title');
        addTearDown(c.dispose);
        c.selection = const TextSelection.collapsed(offset: 5);
        c.setHeader('h1');
        apply(c);
        expect(c.document.text, '${marker}Title');
        c.insertText('\n');
        c.insertText('second');
        c.insertText('\n');
        c.insertText('third');
        expect(levels(c), 'null,null,null', reason: name);
      });

      test('$name: the heading is gone from an emptied heading line too', () {
        final c = RichEditorController(text: 'Title');
        addTearDown(c.dispose);
        c.selection = const TextSelection.collapsed(offset: 5);
        c.setHeader('h2');
        for (var i = 0; i < 5; i++) {
          c.deleteBackward();
        }
        apply(c);
        c.insertText('first');
        expect(levels(c), 'null', reason: name);
        expect(c.document.text, '${marker}first');
      });

      test('$name: several selected heading lines all become items', () {
        final c = RichEditorController(text: 'One\nTwo\nThree');
        addTearDown(c.dispose);
        for (final at in [0, 4, 8]) {
          c.selection = TextSelection.collapsed(offset: at);
          c.setHeader('h1');
        }
        c.selection = const TextSelection(baseOffset: 0, extentOffset: 13);
        apply(c);
        expect(levels(c), 'null,null,null', reason: name);
      });

      test('$name: a heading set on a list item afterwards does not follow the next item', () {
        final c = RichEditorController(text: 'Title');
        addTearDown(c.dispose);
        c.selection = const TextSelection.collapsed(offset: 5);
        apply(c);
        c.setHeader('h1');
        c.selection = TextSelection.collapsed(offset: c.document.text.length);
        c.insertText('\n');
        c.insertText('next');
        expect(levels(c).endsWith(',null'), isTrue, reason: '$name: the new item is not a heading (${levels(c)})');
      });
    }

    test('a list line that is already an item keeps a heading the person gave it', () {
      final c = RichEditorController(text: '- a\n- b');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 3);
      c.setHeader('h2');
      c.selection = const TextSelection.collapsed(offset: 7);
      c.toggleTaskItem(); // b becomes a checklist item; a is untouched
      expect(levels(c), 'h2,null');
    });
  });
}
