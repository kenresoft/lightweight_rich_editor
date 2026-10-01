// Selection on ruled paper: the highlight must be whole ruled rows, continuous
// across lines and paragraphs, include spaces and selected line breaks, and
// keep working with keyboard selection and scrolling.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../rendering/notebook_policy_test.dart' show lay;
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
  boxWidthStyle: ui.BoxWidthStyle.tight,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);

  group('what the field paints with the styles the editor uses (max height, tight width) vs the old tight/tight', () {
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

    test('selecting the last word of a line stays on the word (no band to the right edge)', () {
      // "goes on" ends the first paragraph; the highlight ends with the glyphs.
      final end = text.indexOf(String.fromCharCode(10));
      final bs = boxes(p, TextSelection(baseOffset: end - 4, extentOffset: end), whole: true);
      expect(bs.single.right, lessThan(p.width), reason: 'tight width: stops at the text, not at the layout edge');
      expect(bs.single.right - bs.single.left, lessThan(60));
    });
  });

  group('selected blank lines (a field paints nothing for a line break with no glyphs)', () {
    test('the renderer reports the blank lines a selection runs across, with their rows', () {
      final l = lay('a\n\nb\n\n\nc');
      final r = l.renderer;
      expect(r.blankLinesSelected(0, 8).map((b) => b.offset), [2, 5, 6]);
      expect(r.blankLinesSelected(0, 4).map((b) => b.offset), [2]);
      expect(r.blankLinesSelected(3, 6).map((b) => b.offset), [5], reason: 'chars 3..5 include the line break at 5');
      expect(r.blankLinesSelected(3, 5).map((b) => b.offset), isEmpty, reason: 'the line break at 5 is not selected');
      expect(r.blankLinesSelected(2, 3).map((b) => b.offset), [2]);
      expect(r.blankLinesSelected(4, 4), isEmpty);
      final first = r.blankLinesSelected(0, 8).first;
      expect([first.top, first.bottom], [l.pitch, 2 * l.pitch]);
    });

    test('the last paragraph has no line break to select; a document without blank lines reports none', () {
      expect(lay('a\n').renderer.blankLinesSelected(0, 2), isEmpty);
      expect(lay('a\nb').renderer.blankLinesSelected(0, 3), isEmpty);
    });

    test('the painter marks each with a short bar in the selection colour, under the text', () {
      final l = lay('a\n\nb');
      final canvas = _RectCanvas();
      RuledLinesPainter(
        lineBottoms: l.bottoms,
        selectedBlankLines: l.renderer.blankLinesSelected(0, 4),
        selectionColor: const Color(0x66123456),
        selectionBarLeft: 58,
        selectionBarWidth: 10,
        fallbackLineHeight: l.pitch,
        topPadding: 12,
        scrollOffset: 0,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.solid,
        marginLineX: 44,
      ).paint(canvas, const Size(400, 300));
      expect(canvas.rects.length, 1);
      expect(canvas.rects.single, Rect.fromLTRB(58, 12 + l.pitch, 68, 12 + 2 * l.pitch));
    });

    test('painter repaint rules: a changed selection repaints, an identical one does not', () {
      final l = lay('a\n\nb');
      RuledLinesPainter make(List<BlankLineRegion> lines) => RuledLinesPainter(
        lineBottoms: l.bottoms,
        selectedBlankLines: lines,
        fallbackLineHeight: l.pitch,
        topPadding: 12,
        scrollOffset: 0,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.solid,
        marginLineX: 44,
      );
      final a = make(l.renderer.blankLinesSelected(0, 4));
      expect(make(l.renderer.blankLinesSelected(0, 4)).shouldRepaint(a), isFalse);
      expect(make(const []).shouldRepaint(a), isTrue);
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

    testWidgets('only a focused, non-collapsed selection across a blank line gets a bar', (tester) async {
      final (c, _) = await pump(tester, body: 'one\n\ntwo');
      RuledLinesPainter painter() =>
          tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.painter).whereType<RuledLinesPainter>().single;
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
      await tester.pump();
      expect(c.focusNode.hasFocus, isTrue);
      expect(painter().selectedBlankLines.map((b) => b.offset), [4]);
      c.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(painter().selectedBlankLines, isEmpty);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      expect(painter().selectedBlankLines, isEmpty, reason: 'the blank line is not inside this selection');
      c.focusNode.unfocus();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
      await tester.pump();
      expect(painter().selectedBlankLines, isEmpty, reason: 'no focus: the field hides its selection, so do we');
    });

    testWidgets('the field requests whole-row height, tight width selection boxes', (tester) async {
      await pump(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.selectionHeightStyle, ui.BoxHeightStyle.max);
      expect(field.selectionWidthStyle, ui.BoxWidthStyle.tight);
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

class _RectCanvas implements Canvas {
  final rects = <Rect>[];
  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}
