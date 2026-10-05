// Lists behave the same whatever their depth, kind or neighbours: markers are found at any
// indentation, converting between kinds keeps the depth, numbers count properly through nesting,
// Enter and Backspace step out of nested items, the caret stays out of the marker, and every list
// edit with its renumbering is one undo step.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

RichEditorController editor(String text, {int? caret, int? base}) {
  final c = RichEditorController(text: text);
  addTearDown(c.dispose);
  final at = caret ?? text.length;
  c.selection = base == null ? TextSelection.collapsed(offset: at) : TextSelection(baseOffset: base, extentOffset: at);
  return c;
}

String spaces(int n) => ' ' * n;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a marker is found however deep the item is', () {
    for (final n in [0, 2, 12, 20, 26, 40]) {
      test('indent $n: every kind keeps being a list, and the checkbox is not lost', () {
        for (final marker in ['- ', '1. ', '- [ ] ', '- [x] ']) {
          final line = '${spaces(n)}${marker}item';
          expect(listPrefixLength(line, 0), n + marker.length, reason: '"$line"');
          expect(listIndentWhitespace(line, 0).length, n);
        }
      });

      test('indent $n: Enter continues the same kind at the same depth', () {
        final bullet = editor('${spaces(n)}- item')..insertText('\n');
        expect(bullet.document.text, '${spaces(n)}- item\n${spaces(n)}- ');
        final check = editor('${spaces(n)}- [ ] item')..insertText('\n');
        expect(check.document.text, '${spaces(n)}- [ ] item\n${spaces(n)}- [ ] ');
        final numbered = editor('${spaces(n)}1. item')..insertText('\n');
        expect(numbered.document.text, '${spaces(n)}1. item\n${spaces(n)}2. ');
      });
    }
  });

  group('changing the kind of a line keeps its depth', () {
    for (final n in [0, 2, 8, 20]) {
      test('indent $n', () {
        final fromCheck = editor('${spaces(n)}- [ ] item')..toggleBulletList();
        expect(fromCheck.document.text, '${spaces(n)}- item', reason: 'Bullet on a checklist item makes a plain bullet');
        final fromNumbered = editor('${spaces(n)}1. item')..toggleBulletList();
        expect(fromNumbered.document.text, '${spaces(n)}- item');
        final bulletToCheck = editor('${spaces(n)}- item')..toggleChecklist();
        expect(bulletToCheck.document.text, '${spaces(n)}- [ ] item');
        final numberedToCheck = editor('${spaces(n)}1. item')..toggleChecklist();
        expect(numberedToCheck.document.text, '${spaces(n)}- [ ] item');
        final checkToNumbered = editor('${spaces(n)}- [x] item')..toggleNumberedList();
        expect(checkToNumbered.document.text, '${spaces(n)}1. item');
      });
    }

    test('Bullet twice is back to plain text, and so is Checklist and Numbers', () {
      for (final apply in <void Function(RichEditorController)>[
        (c) => c.toggleBulletList(),
        (c) => c.toggleChecklist(),
        (c) => c.toggleNumberedList(),
      ]) {
        final c = editor('item');
        apply(c);
        expect(listPrefixLength(c.document.text, 0), greaterThan(0));
        apply(c);
        expect(c.document.text, 'item');
      }
    });

    test('the Checklist button never ticks a box; tapping the box does', () {
      final c = editor('  - [ ] item', caret: 8);
      c.toggleChecklist();
      expect(c.document.text, 'item', reason: 'the boxes go');
      final d = editor('  - [ ] item', caret: 8);
      d.toggleTaskItem();
      expect(d.document.text, '  - [x] item');
      d.toggleTaskItem();
      expect(d.document.text, '  - [ ] item');
    });

    test('a ticked item stays ticked when it is pressed with Checklist alongside unticked lines', () {
      final c = editor('- [x] a\nb', caret: 9, base: 0);
      c.toggleChecklist();
      expect(c.document.text, '- [x] a\n- [ ] b');
    });

    test('plain text that starts with spaces keeps them as depth, not as part of the text', () {
      final bullet = editor('    hello')..toggleBulletList();
      expect(bullet.document.text, '    - hello');
      final check = editor('    hello')..toggleChecklist();
      expect(check.document.text, '    - [ ] hello');
      final numbered = editor('    hello')..toggleNumberedList();
      expect(numbered.document.text, '    1. hello');
    });

    test('a mixed selection becomes one kind at consistent depths', () {
      final c = editor('- a\n1. b\n- [ ] c\nd', base: 0);
      c.toggleBulletList();
      expect(c.document.text, '- a\n- b\n- c\n- d');
    });

    test('a nested item keeps its depth when the kind is switched in a mixed selection', () {
      final c = editor('1. a\n    - b', base: 0);
      c.toggleNumberedList();
      expect(c.document.text, '1. a\n    1. b');
    });
  });

  group('numbers count properly through nesting', () {
    const three = '1. a\n2. b\n3. c';

    test('indenting the middle item starts a nested list at 1 and closes the gap', () {
      final c = editor(three, caret: 7)..indentList();
      expect(c.document.text, '1. a\n  1. b\n2. c');
    });

    test('indenting the last item, then the one above it', () {
      final c = editor(three)..indentList();
      expect(c.document.text, '1. a\n2. b\n  1. c');
      c.selection = const TextSelection.collapsed(offset: 8);
      c.indentList();
      expect(c.document.text, '1. a\n  1. b\n  2. c');
    });

    test('outdenting puts them back in the one count', () {
      final c = editor(three, caret: 7)..indentList();
      c.outdentList();
      expect(c.document.text, three);
    });

    test('Enter after an item that has children numbers the new one and the next parent', () {
      final c = editor('1. a\n  1. x\n2. b', caret: 4);
      c.insertText('\n');
      expect(c.document.text, '1. a\n2. \n  1. x\n3. b');
    });

    test('a bullet at the same depth ends a numbered run; the numbers after it start again', () {
      final c = editor('1. a\n- b\n2. c', caret: 4)..insertText('\n');
      expect(c.document.text, '1. a\n2. \n- b\n1. c');
    });

    test('deleting an item renumbers the ones after it in the same undo step', () {
      final c = editor('1. a\n2. b\n3. c\n4. d', base: 5, caret: 10);
      c.deleteSelection();
      expect(c.document.text, '1. a\n2. c\n3. d');
      c.undo();
      expect(c.document.text, '1. a\n2. b\n3. c\n4. d', reason: 'one undo restores the lot');
    });

    test('a toggle to numbers and its renumbering are one undo step', () {
      final c = editor('1. a\nb\n3. c', caret: 6);
      c.toggleNumberedList();
      expect(c.document.text, '1. a\n2. b\n3. c');
      c.undo();
      expect(c.document.text, '1. a\nb\n3. c');
    });

    test('ten items: the caret follows the digit that grew', () {
      final items = [for (var i = 1; i <= 9; i++) '$i. item$i'].join('\n');
      final c = editor(items, caret: 8); // the end of the first item
      c.insertText('\n');
      expect(c.document.text.split('\n').last, '10. item9');
      expect(c.selection.baseOffset, '1. item1\n2. '.length, reason: 'the caret is in the new, empty item');
    });
  });

  group('Enter and Backspace step out of a nested item before they leave the list', () {
    test('Enter on an empty nested bullet moves it out one level; at the top it leaves the list', () {
      final c = editor('- a\n      - ');
      c.insertText('\n');
      expect(c.document.text, '- a\n    - ');
      c.insertText('\n');
      expect(c.document.text, '- a\n  - ');
      c.insertText('\n');
      expect(c.document.text, '- a\n', reason: 'the first level is the top: this leaves the list');
      c.insertText('after');
      expect(c.document.text, '- a\nafter');
    });

    test('the same for a nested numbered item, and the counts follow', () {
      final c = editor('1. a\n    1. ');
      c.insertText('\n');
      expect(c.document.text, '1. a\n  1. ');
      expect(c.selection.baseOffset, c.document.text.length);
    });

    test('Backspace at the start of a nested item moves it out; at the top it removes the marker', () {
      final c = editor('- a\n    - item', caret: 10);
      c.deleteBackward();
      expect(c.document.text, '- a\n  - item');
      c.deleteBackward();
      expect(c.document.text, '- a\nitem');
    });

    test('Backspace on a numbered item removes its marker and the next ones count on', () {
      final c = editor('1. a\n2. b\n3. c', caret: 8);
      c.deleteBackward();
      expect(c.document.text, '1. a\nb\n1. c');
    });
  });

  group('indent limits and the deepest level', () {
    test('Indent stops at six levels', () {
      final c = editor('- item');
      for (var i = 0; i < 20; i++) {
        c.indentList();
      }
      expect(listIndentWhitespace(c.document.text, 0).length, maxListIndent);
    });

    test('an item already deeper than that is not pushed further, and can still come back', () {
      final c = editor('${spaces(30)}- item');
      c.indentList();
      expect(listIndentWhitespace(c.document.text, 0).length, 30);
      c.outdentList();
      expect(listIndentWhitespace(c.document.text, 0).length, 28);
    });

    test('Outdent at the left edge does nothing', () {
      final c = editor('- item');
      c.outdentList();
      expect(c.document.text, '- item');
    });
  });

  group('the caret stays out of the marker', () {
    test('a caret put inside the marker goes to where the text starts', () {
      for (final offset in [0, 1, 2, 3, 4, 5]) {
        final c = editor('  - [ ] item', caret: offset);
        expect(c.selection.baseOffset, 8, reason: 'from $offset');
      }
    });

    test('typing there lands after the marker', () {
      final c = editor('- item', caret: 0);
      c.insertText('x');
      expect(c.document.text, '- xitem');
    });

    test('left from the start of the text goes to the end of the line above', () {
      final c = editor('first\n- item', caret: 8);
      expect(c.selection.baseOffset, 8);
      c.selection = const TextSelection.collapsed(offset: 7); // the arrow key moves one to the left
      expect(c.selection.baseOffset, 5);
    });

    test('left from the start of the first line stays put', () {
      final c = editor('- item', caret: 2);
      c.selection = const TextSelection.collapsed(offset: 1);
      expect(c.selection.baseOffset, 2);
    });

    test('right from the end of the line above skips the marker', () {
      final c = editor('first\n- item', caret: 5);
      c.selection = const TextSelection.collapsed(offset: 6);
      expect(c.selection.baseOffset, 8);
    });

    test('a range selection that starts at the marker is left alone', () {
      final c = editor('- item', base: 0, caret: 6);
      expect(c.selection.baseOffset, 0);
      expect(c.selection.extentOffset, 6);
    });

    test('plain text and code are not touched', () {
      final plain = editor('one two', caret: 0);
      expect(plain.selection.baseOffset, 0);
    });
  });
  // What the keyboard does: it hands the field a new value (the old text with the keystroke
  // applied) and the controller works out the edit.
  group('typing on the keyboard', () {
    void keystroke(RichEditorController c, {required int at, int removed = 0, String insert = ''}) {
      final text = c.document.text;
      final next = text.replaceRange(at, at + removed, insert);
      c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at + insert.length));
    }

    test('Enter after an item with children numbers the new item and the next parent', () {
      final c = editor('1. a\n  1. x\n2. b', caret: 4);
      keystroke(c, at: 4, insert: '\n');
      expect(c.document.text, '1. a\n2. \n  1. x\n3. b');
      expect(c.selection.baseOffset, '1. a\n2. '.length);
      c.undo();
      expect(c.document.text, '1. a\n  1. x\n2. b', reason: 'one undo');
    });

    test('Enter on an empty nested item steps out, then leaves', () {
      final c = editor('- a\n    - ');
      keystroke(c, at: c.document.text.length, insert: '\n');
      expect(c.document.text, '- a\n  - ');
      keystroke(c, at: c.document.text.length, insert: '\n');
      expect(c.document.text, '- a\n');
    });

    test('Backspace at the start of an item removes the marker and the numbers after it start again', () {
      final c = editor('1. a\n2. b\n3. c', caret: 8);
      keystroke(c, at: 7, removed: 1);
      expect(c.document.text, '1. a\nb\n1. c');
      expect(c.selection.baseOffset, 5);
    });

    test('Backspace at the start of a nested item moves it out', () {
      final c = editor('1. a\n    1. b', caret: 12);
      keystroke(c, at: 11, removed: 1);
      expect(c.document.text, '1. a\n  1. b');
    });

    test('typing in an item is not wrapped in anything: typing still undoes as one step', () {
      final c = editor('- ');
      for (final ch in 'hello'.split('')) {
        keystroke(c, at: c.document.text.length, insert: ch);
      }
      expect(c.document.text, '- hello');
      c.undo();
      expect(c.document.text, '- ');
    });

    test('a multi-line paste into a numbered list leaves the numbers counting', () {
      final c = editor('1. a\n2. b', caret: 4);
      keystroke(c, at: 4, insert: '\n7. x\n9. y');
      expect(c.document.text, '1. a\n2. x\n3. y\n4. b');
    });

    test('a caret tapped into the marker is moved after it', () {
      final c = editor('- item', caret: 6);
      c.value = c.value.copyWith(selection: const TextSelection.collapsed(offset: 1));
      expect(c.selection.baseOffset, 2);
    });
  });
}
