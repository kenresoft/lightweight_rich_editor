// Cutting a picture removes it whole, wherever it sits: after plain text, after a code block,
// between code blocks, at the end of the note.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

int _imageRows(RichEditorController c) => c.document.paragraphs.records.where((r) => isImageLevel(r.headerLevel)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clip;
  setUp(() {
    clip = null;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      if (call.method == 'Clipboard.getData') return clip == null ? null : {'text': clip};
      return null;
    });
  });

  RichEditorController build({required bool code, String after = ''}) {
    final c = RichEditorController(text: 'print(1)\nprint(2)', theme: notebookTheme);
    if (code) {
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 17);
      c.toggleCodeBlock();
    }
    c.selection = const TextSelection.collapsed(offset: 17);
    c.insertImageBlock('pic', rows: 5);
    if (after.isNotEmpty) {
      c.insertText(after);
    }
    return c;
  }

  for (final code in [false, true]) {
    for (final how in ['whole run', 'rows only', 'one row', 'from line break above', 'caret on picture + select all rows']) {
      test('${code ? "code block" : "plain text"} above: cut the picture ($how)', () async {
        final c = build(code: code, after: 'tail');
        addTearDown(c.dispose);
        final run = c.imageRuns.single;
        expect(run.rows, 5);
        switch (how) {
          case 'whole run':
            c.selection = TextSelection(baseOffset: run.start, extentOffset: run.end);
          case 'rows only':
            c.selection = TextSelection(baseOffset: run.start + 1, extentOffset: run.end);
          case 'one row':
            c.selection = TextSelection(baseOffset: run.start, extentOffset: run.start + 1);
          case 'from line break above':
            c.selection = TextSelection(baseOffset: run.start - 1, extentOffset: run.end);
          default:
            c.selection = TextSelection(baseOffset: run.start, extentOffset: run.end);
        }
        await c.cut();
        final survivors = _imageRows(c);
        // either the whole picture goes, or it is left whole: never a shorter one
        expect(survivors == 0 || survivors == 5, isTrue, reason: 'left $survivors rows of a 5-row picture');
        expect(c.text.contains('tail'), isTrue);
        expect(c.text.contains('print(2)'), isTrue);
      });
    }
  }

  for (final code in [false, true]) {
    for (final spot in ['end of the code line', 'new line under the block', 'start of the tail']) {
      test('${code ? "code block" : "plain text"}: cut then paste at $spot keeps a 5-row picture', () async {
        final c = build(code: code, after: 'tail');
        addTearDown(c.dispose);
        final run = c.imageRuns.single;
        c.selection = TextSelection(baseOffset: run.start, extentOffset: run.end);
        await c.cut();
        expect(_imageRows(c), 0);
        switch (spot) {
          case 'end of the code line':
            c.selection = const TextSelection.collapsed(offset: 17);
          case 'new line under the block':
            c.selection = const TextSelection.collapsed(offset: 17);
            c.insertText('\n');
          default:
            c.selection = TextSelection.collapsed(offset: c.text.indexOf('tail'));
        }
        await c.paste();
        final rows = _imageRows(c);
        expect(rows, 5, reason: 'pasted picture has $rows rows; text=${c.text.replaceAll("\n", "|")}');
        expect(c.imageRuns.length, 1);
      });
    }
  }
}
