// Selection on ruled paper: the highlight must be whole ruled rows, continuous
// across lines and paragraphs, include spaces and selected line breaks, and
// keep working with keyboard selection and scrolling.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

const text = 'hello big world and a long wrapping line that goes on\nsecond para   with  gaps  \n\nfourth';

TextPainter paragraph({double width = 200, double pitch = 30}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: 'Roboto', fontSize: 16, height: pitch / 16, leadingDistribution: TextLeadingDistribution.proportional),
    ),
    strutStyle: StrutStyle(
      fontFamily: 'Roboto',
      fontSize: 16,
      height: pitch / 16,
      forceStrutHeight: true,
      leading: 0,
      leadingDistribution: TextLeadingDistribution.proportional,
    ),
    textDirection: TextDirection.ltr,
    textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.proportional),
  )..layout(maxWidth: width);
}

List<TextBox> boxes(TextPainter p, TextSelection s, {required bool whole}) => p.getBoxesForSelection(
  s,
  boxHeightStyle: whole ? ui.BoxHeightStyle.max : ui.BoxHeightStyle.tight,
  boxWidthStyle: whole ? ui.BoxWidthStyle.max : ui.BoxWidthStyle.tight,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);

  group('what the field paints with the styles the editor uses (max/max) vs the old tight/tight', () {
    late TextPainter p;
    setUp(() => p = paragraph());

    test('one word: the box is the whole ruled row, not just the glyph band', () {
      const sel = TextSelection(baseOffset: 6, extentOffset: 9);
      final whole = boxes(p, sel, whole: true).single;
      final tight = boxes(p, sel, whole: false).single;
      expect([whole.top, whole.bottom], [0, 30]);
      expect(tight.bottom - tight.top, lessThan(25), reason: 'tight leaves the rest of the row unselected');
    });

    test('a word plus its trailing space, and a space on its own, have width', () {
      final withSpace = boxes(p, const TextSelection(baseOffset: 6, extentOffset: 10), whole: true).single;
      final word = boxes(p, const TextSelection(baseOffset: 6, extentOffset: 9), whole: true).single;
      expect(withSpace.right, greaterThan(word.right));
      final space = boxes(p, const TextSelection(baseOffset: 9, extentOffset: 10), whole: true).single;
      expect(space.right - space.left, greaterThan(2));
    });

    test('a wrapped / multi-paragraph selection is one gap-free band of whole rows', () {
      for (final sel in const [
        TextSelection(baseOffset: 0, extentOffset: 40),
        TextSelection(baseOffset: 30, extentOffset: 80),
        TextSelection(baseOffset: 0, extentOffset: text.length),
      ]) {
        final bs = boxes(p, sel, whole: true);
        final rows = <double, List<TextBox>>{};
        for (final b in bs) {
          rows.putIfAbsent(b.top, () => []).add(b);
          expect(b.bottom - b.top, 30, reason: 'every box is a whole row');
          expect(b.top % 30, 0);
        }
        final tops = rows.keys.toList()..sort();
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i] - tops[i - 1], 30, reason: 'no unselected row between selected rows ($sel)');
        }
      }
    });

    test('a selected blank paragraph shows as a full-width bar; the selected line break is visible', () {
      final bs = boxes(p, const TextSelection(baseOffset: 76, extentOffset: 82), whole: true);
      expect(bs.any((b) => b.left == 0 && b.right > 150), isTrue, reason: 'blank line selected as a bar');
      // Selecting through a line break: the highlight carries on past the last glyph
      // (to the widest line), where tight boxes would stop at the glyphs.
      final nl = text.indexOf(String.fromCharCode(10));
      const pad = 10;
      final sel = TextSelection(baseOffset: nl - pad, extentOffset: nl + 3);
      double reach(List<TextBox> b) => b.map((x) => x.right).reduce((a, c) => a > c ? a : c);
      expect(reach(boxes(p, sel, whole: true)), greaterThanOrEqualTo(reach(boxes(p, sel, whole: false))));
      expect(boxes(p, sel, whole: true).length, greaterThanOrEqualTo(boxes(p, sel, whole: false).length));
    });
  });

  group('mounted editor', () {
    Future<(RichEditorController, ScrollController)> pump(WidgetTester tester, {String body = text, double height = 600}) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(500, height);
      addTearDown(tester.view.reset);
      final c = RichEditorController(text: body, theme: notebookTheme);
      final scroll = ScrollController();
      addTearDown(c.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(body: RichTextEditor(controller: c, scrollController: scroll, autofocus: true)),
      ));
      await tester.pumpAndSettle();
      return (c, scroll);
    }

    testWidgets('the field requests whole-row, max-width selection boxes', (tester) async {
      await pump(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.selectionHeightStyle, ui.BoxHeightStyle.max);
      expect(field.selectionWidthStyle, ui.BoxWidthStyle.max);
    });

    testWidgets('Shift+Arrow extends the selection one character at a time, including over spaces and line breaks', (tester) async {
      final (c, _) = await pump(tester, body: 'ab cd\nef');
      c.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.selection.baseOffset, 1);
      expect(c.selection.extentOffset, 7, reason: 'over "b", " ", "cd", the line break and "e"');
    });

    testWidgets('Shift+Down selects whole lines; Shift+Home/End select to the line edges', (tester) async {
      final (c, _) = await pump(tester, body: 'first line\nsecond line');
      c.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.selection.extentOffset, greaterThan(11));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.selection.extentOffset, 'first line\nsecond line'.length);
    });

    testWidgets('select-all selects everything and the selection survives a formatting change', (tester) async {
      final (c, _) = await pump(tester);
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.document.text.length);
      c.toggleBold();
      await tester.pump();
      expect(c.selection, TextSelection(baseOffset: 0, extentOffset: c.document.text.length));
      expect(c.isAttributeActive(AttributeType.bold), isTrue);
    });

    testWidgets('selection stays attached to the same text while the editor scrolls', (tester) async {
      final long = List.generate(60, (i) => 'line $i with some words').join('\n');
      final (c, scroll) = await pump(tester, body: long, height: 300);
      final start = long.indexOf('line 40');
      c.selection = TextSelection(baseOffset: start, extentOffset: start + 12);
      await tester.pump();
      scroll.jumpTo(scroll.position.maxScrollExtent / 2);
      await tester.pump();
      scroll.jumpTo(0);
      await tester.pump();
      expect(c.selection, TextSelection(baseOffset: start, extentOffset: start + 12));
      expect(c.document.text.substring(c.selection.start, c.selection.end), 'line 40 with');
    });
  });
}
