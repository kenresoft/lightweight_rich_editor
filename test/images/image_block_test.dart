// An image is a block of blank rows. These tests exercise the document model
// (insert, edit around, delete, resize, undo, save/load), without any painting.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';
import '../rendering/notebook_policy_test.dart' show lay;

String? _lv(RichEditorController c, int i) => c.document.paragraphs.records[i].headerLevel;
List<String?> _levels(RichEditorController c) => [for (final r in c.document.paragraphs.records) r.headerLevel];
int _imageRows(RichEditorController c) => c.document.paragraphs.records.where((r) => isImageLevel(r.headerLevel)).length;

void main() {
  RichEditorController make(String text) => RichEditorController(text: text, theme: notebookTheme);

  void type(RichEditorController c, String insert) {
    final sel = c.selection;
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, insert),
      selection: TextSelection.collapsed(offset: sel.start + insert.length),
    );
  }

  void backspace(RichEditorController c) {
    final sel = c.selection;
    final from = sel.isCollapsed ? sel.start - 1 : sel.start;
    c.value = TextEditingValue(
      text: c.text.replaceRange(from, sel.end, ''),
      selection: TextSelection.collapsed(offset: from),
    );
  }

  group('insert', () {
    test('on an empty line: n image rows, then a normal line, caret on it', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic1', rows: 4);
      expect(_imageRows(c), 4);
      expect(c.document.paragraphs.length, 5, reason: '4 rows + the line after');
      expect(c.text, '\n\n\n\n', reason: 'no placeholder characters: an image reads as blank lines');
      expect(_lv(c, 4), isNull);
      expect(c.selection.baseOffset, 4, reason: 'on the line after the picture');
      expect(imageIdOf(_lv(c, 0)), 'pic1');
      expect(_levels(c).sublist(0, 4).toSet().length, 1, reason: 'one block: every row shares one level');
    });

    test('mid-line: the text before stays above, the text after goes below', () {
      final c = make('hello world');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic1', rows: 3);
      expect(c.text, 'hello\n\n\n\n world');
      expect(_lv(c, 0), isNull);
      expect(_imageRows(c), 3);
      expect(c.document.paragraphs.records[4].start, c.selection.baseOffset);
      expect(c.text.substring(c.selection.baseOffset), ' world');
    });

    test('at the start of a line with text: the line moves below the picture', () {
      final c = make('hello');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 0);
      c.insertImageBlock('pic1', rows: 3);
      expect(c.text, '\n\n\nhello');
      expect(_imageRows(c), 3);
      expect(_lv(c, 3), isNull);
    });

    test('with the caret on another picture: below it, as a separate block', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('one', rows: 3);
      c.selection = const TextSelection.collapsed(offset: 1); // on a row of the first picture
      c.insertImageBlock('two', rows: 3);
      expect(_imageRows(c), 6);
      expect(c.imageRunAt(0)!.id, 'one');
      expect(c.imageRunAt(0)!.rows, 3);
      final second = c.imageRunAt(c.document.length - 1) ?? c.imageRunAt(4);
      expect(second!.id, 'two');
      expect(second.rows, 3);
    });

    test('pasting the same picture twice in a row gives two blocks, not one tall one', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('same', rows: 3);
      c.insertImageBlock('same', rows: 3);
      final runs = <ImageRun>{};
      for (var i = 0; i < c.document.length; i++) {
        final r = c.imageRunAt(i);
        if (r != null) runs.add(r);
      }
      expect(runs.length, 2);
      expect(runs.every((r) => r.rows == 3), isTrue);
    });

    test('a whole insert is one undo step, and redo brings it back', () {
      final c = make('hello');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic1', rows: 4);
      expect(_imageRows(c), 4);
      c.undo();
      expect(c.text, 'hello');
      expect(_imageRows(c), 0);
      c.redo();
      expect(_imageRows(c), 4);
    });

    test('rows are clamped; ids must be safe', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('a', rows: 1);
      expect(_imageRows(c), minImageRows);
      c.insertImageBlock('bad id/..', rows: 3);
      expect(c.imageRunAt(c.document.length), isNull, reason: 'an unsafe id is refused');
    });

    test('rowsForImage follows the aspect ratio within bounds', () {
      expect(rowsForImage(300, 300), 10);
      expect(rowsForImage(400, 300), 8);
      expect(rowsForImage(1000, 100), minImageRows);
      expect(rowsForImage(100, 1000), 12);
      expect(rowsForImage(0, 0), 8);
    });
  });

  group('editing around a picture', () {
    RichEditorController withPicture() {
      final c = make('top\n');
      c.selection = const TextSelection.collapsed(offset: 4);
      c.insertImageBlock('pic', rows: 3);
      return c; // 'top', 3 image rows, an empty normal line; caret on that line
    }

    test('typing while the picture is selected continues on a new line below it', () {
      final c = withPicture();
      addTearDown(c.dispose);
      c.selection = TextSelection.collapsed(offset: c.imageRunAt(5)!.end); // the bottom row // on a row of the picture
      type(c, 'x');
      expect(_imageRows(c), 3, reason: 'the picture is untouched');
      expect(c.text.contains('x'), isTrue);
      final i = c.text.indexOf('x');
      expect(c.document.paragraphs.paragraphAt(i)!.headerLevel, isNull, reason: 'the typed text is on an ordinary line');
      expect(c.selection.baseOffset, i + 1);
    });

    test('Enter while the picture is selected adds an ordinary line below it, not another row', () {
      final c = withPicture();
      addTearDown(c.dispose);
      c.selection = TextSelection.collapsed(offset: c.imageRunAt(5)!.end); // the bottom row
      type(c, '\n');
      expect(_imageRows(c), 3);
      expect(c.document.paragraphs.length, 7);
    });

    test('Enter with the caret in the picture\'s upper half adds an ordinary line above it', () {
      final c = withPicture();
      addTearDown(c.dispose);
      final run = c.imageRunAt(5)!;
      c.selection = TextSelection.collapsed(offset: run.start); // top row
      final before = c.text.length;
      type(c, '\n');
      expect(c.text.length, before + 1);
      expect(_imageRows(c), 3, reason: 'the picture is whole');
      final top = c.document.paragraphs.paragraphAt(run.start)!;
      expect(top.headerLevel, isNull, reason: 'the new line is ordinary');
      expect(c.imageRunAt(run.start + 1)!.rows, 3);
      expect(c.selection.baseOffset, run.start, reason: 'the caret is on the new line');
      c.undo();
      expect(c.text.length, before);
      expect(c.imageRunAt(run.start)!.rows, 3);
    });

    test('typing in the upper half goes above the picture, in the lower half below it', () {
      final c = withPicture();
      addTearDown(c.dispose);
      final run = c.imageRunAt(5)!;
      c.selection = TextSelection.collapsed(offset: run.start);
      type(c, 'up');
      expect(c.text.indexOf('up'), run.start);
      expect(c.document.paragraphs.paragraphAt(run.start)!.headerLevel, isNull);
      expect(c.selection.baseOffset, run.start + 2);
      expect(c.imageRunAt(run.start + 3)!.rows, 3);

      final run2 = c.imageRunAt(run.start + 3)!;
      c.selection = TextSelection.collapsed(offset: run2.end); // bottom row
      type(c, 'down');
      expect(c.text.indexOf('down'), greaterThan(run2.end));
      expect(c.imageRunAt(run2.start)!.rows, 3);
    });

    test('a picture at the very start of the note can get a line above it', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic', rows: 4);
      c.selection = const TextSelection.collapsed(offset: 0);
      type(c, '\n');
      expect(c.document.paragraphs.recordAt(0).headerLevel, isNull);
      expect(c.imageRunAt(1)!.rows, 4);
      type(c, 'x'); // the caret is on the new empty line
      expect(c.text.startsWith('x\n'), isTrue);
    });

    test('Backspace on the picture removes the whole picture, in one undo step', () {
      final c = withPicture();
      addTearDown(c.dispose);
      final before = c.text;
      c.selection = const TextSelection.collapsed(offset: 5);
      backspace(c);
      expect(_imageRows(c), 0);
      expect(c.text, 'top\n');
      c.undo();
      expect(_imageRows(c), 3);
      expect(c.text, before);
    });

    test('Backspace at the start of the text line under a picture steps into it; a second removes it', () {
      final c = make('top\n');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 4);
      c.insertImageBlock('pic', rows: 3);
      type(c, 'below'); // the caret was on the line after the picture
      final below = c.text.indexOf('below');
      c.selection = TextSelection.collapsed(offset: below);
      backspace(c);
      expect(_imageRows(c), 3, reason: 'nothing was removed');
      expect(c.text.contains('below'), isTrue);
      expect(c.selectedImageRun, isNotNull, reason: 'the caret stepped onto the picture');
      backspace(c);
      expect(_imageRows(c), 0);
      expect(c.text, 'top\nbelow');
      expect(c.document.paragraphs.records.every((r) => !isImageLevel(r.headerLevel)), isTrue);
    });

    test('Backspace on an empty line under a picture just removes the line', () {
      final c = withPicture();
      addTearDown(c.dispose);
      final length = c.text.length;
      backspace(c); // caret on the empty line after the picture
      expect(c.text.length, length - 1);
      expect(_imageRows(c), 3, reason: 'the picture stays whole');
    });

    test('deleting the whole picture at the end of a note leaves no stray image row', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic', rows: 3);
      c.selection = const TextSelection.collapsed(offset: 1); // on a row of the picture
      backspace(c);
      expect(c.document.paragraphs.records.where((r) => isImageLevel(r.headerLevel)), isEmpty);
      expect(c.text, '');
    });

    test('Delete at the end of the line above a picture does not join the picture into it', () {
      final c = withPicture();
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 3); // end of "top"
      final sel = c.selection;
      c.value = TextEditingValue(text: c.text.replaceRange(sel.start, sel.start + 1, ''), selection: sel);
      expect(c.text.startsWith('top\n'), isTrue);
      expect(_imageRows(c), 3);
    });

    test('programmatic insertText and paste on a picture step out below it first', () {
      final c = withPicture();
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertText('hi');
      expect(_imageRows(c), 3);
      expect(c.text.contains('hi'), isTrue);
      expect(c.document.paragraphs.paragraphAt(c.text.indexOf('hi'))!.headerLevel, isNull);
    });

    test('editing text far from a picture is untouched by the guard', () {
      final c = withPicture();
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 3);
      type(c, '!');
      expect(c.text.startsWith('top!\n'), isTrue);
      expect(_imageRows(c), 3);
    });
  });

  group('resize', () {
    test('taller adds rows to the same block; shorter removes them; limits hold', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic', rows: 4);
      var run = c.imageRunAt(0)!;
      c.resizeImage(run, 2);
      run = c.imageRunAt(0)!;
      expect(run.rows, 6);
      expect(c.document.paragraphs.length, 7, reason: '6 rows + the line after');
      c.resizeImage(run, -3);
      run = c.imageRunAt(0)!;
      expect(run.rows, 3);
      c.resizeImage(run, -5);
      expect(c.imageRunAt(0)!.rows, minImageRows);
      c.resizeImage(c.imageRunAt(0)!, 99);
      expect(c.imageRunAt(0)!.rows, maxImageRows);
      expect(_levels(c).whereType<String>().toSet().length, 1, reason: 'still a single block');
    });

    test('a resize is one undo step', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic', rows: 4);
      c.resizeImage(c.imageRunAt(0)!, 2);
      c.undo();
      expect(c.imageRunAt(0)!.rows, 4);
    });
  });

  group('save and load', () {
    test('an image block survives toJson / fromJson with its rows', () {
      final c = make('intro');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic9', rows: 5);
      type(c, 'after');
      final json = c.document.toJson();
      final loaded = EditorDocument.fromJson(json);
      final c2 = RichEditorController(text: loaded.text, initialAttributes: loaded.exportAttributes());
      addTearDown(c2.dispose);
      expect(c2.text, c.text);
      final run = c2.imageRunAt(c2.text.indexOf('\n') + 1);
      expect(run, isNotNull);
      expect(run!.id, 'pic9');
      expect(run.rows, 5);
      expect(c2.document.paragraphs.paragraphAt(c2.text.indexOf('after'))!.headerLevel, isNull);
    });

    test('two blocks of the same picture stay two blocks after a round trip', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('same', rows: 3);
      c.insertImageBlock('same', rows: 4);
      final loaded = EditorDocument.fromJson(c.document.toJson());
      final c2 = RichEditorController(text: loaded.text, initialAttributes: loaded.exportAttributes());
      addTearDown(c2.dispose);
      final runs = <ImageRun>{};
      for (var i = 0; i < c2.document.length; i++) {
        final r = c2.imageRunAt(i);
        if (r != null) runs.add(r);
      }
      expect(runs.map((r) => r.rows).toList()..sort(), [3, 4]);
    });
  });

  group('layout', () {
    test('a block lays out as exactly its rows, aligned to the ruled grid', () {
      final c = make('top\n');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 4);
      c.insertImageBlock('pic', rows: 4);
      final l = lay(c.text, attrs: c.document.exportAttributes(), dpr: 1.0);
      final regions = l.renderer.imageBlocks;
      expect(regions, hasLength(1));
      final r = regions.single;
      expect(r.rows, 4);
      expect(r.id, 'pic');
      expect((r.bottom - r.top) / l.pitch, closeTo(4, 0.01));
      expect(r.top % l.pitch, closeTo(0, 0.02), reason: 'starts on a rule');
      l.expectEveryLineOneRow();
    });

    test('a level in two separate runs is drawn once (a broken block does not show twice)', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic', rows: 4);
      // break the block in two with an ordinary line in the middle
      final level = _lv(c, 0)!;
      final attrs = [
        TextAttribute(start: 0, end: 1, type: AttributeType.header, value: level),
        TextAttribute(start: 2, end: 3, type: AttributeType.header, value: level),
      ];
      final l = lay('\n\n\n\n', attrs: attrs, dpr: 1.0);
      expect(l.renderer.imageBlocks, hasLength(1));
    });

    test('image rows are not blank-line selection targets', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic', rows: 3);
      type(c, '\n'); // an ordinary empty line after the picture, with a line after it
      final l = lay(c.text, attrs: c.document.exportAttributes(), dpr: 1.0);
      expect(l.renderer.blankLinesSelected(0, c.text.length), hasLength(1), reason: 'only the ordinary empty line, not the picture rows');
    });
  });
}
