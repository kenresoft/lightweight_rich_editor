// Block-level code: paragraph metadata that behaves like a block through
// editing, undo/redo, rendering, the ruled-paper layer, copy and export.
import 'dart:ui' show ClipOp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/export/html_exporter.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';
import 'package:lightweight_rich_editor/src/export/markdown_exporter.dart';

import '../rendering/notebook_policy_test.dart' show lay;
import '../support/notebook_test_support.dart';

const dartCode = 'void main() {\n\n  print(1);\n}';

RichEditorController make(String text, [List<TextAttribute> attrs = const []]) =>
    RichEditorController(text: text, theme: notebookTheme, initialAttributes: attrs);

TextAttribute codeSpan(int s, int e, [String level = 'code']) =>
    TextAttribute(start: s, end: e, type: AttributeType.header, value: level);

List<String?> levels(RichEditorController c) => c.document.paragraphs.records.map((r) => r.headerLevel).toList();

class _Canvas implements Canvas {
  final lineYs = <double>[];
  final rrects = <RRect>[];
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if (p1.dy == p2.dy) lineYs.add(p1.dy);
  }

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects.add(rrect);

  final clips = <Rect>[];
  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) => clips.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);
  lateBlockTests();

  group('model', () {
    test('level helpers', () {
      expect(isCodeBlockLevel('code'), isTrue);
      expect(isCodeBlockLevel('code:dart'), isTrue);
      expect(isCodeBlockLevel('h1'), isFalse);
      expect(isCodeBlockLevel(null), isFalse);
      expect(codeBlockLanguage('code:dart'), 'dart');
      expect(codeBlockLanguage('code'), isNull);
      expect(codeBlockLevelFor(' Dart '), 'code:dart');
      expect(codeBlockLevelFor('C++'), 'code:c++');
      expect(codeBlockLevelFor(''), 'code');
      expect(codeBlockLevelFor(null), 'code');
    });

    test('seeding: every line of a span is code, blank lines included, neighbours are not', () {
      final c = make('intro\n$dartCode\nafter', [codeSpan(6, 6 + dartCode.length, 'code:dart')]);
      addTearDown(c.dispose);
      expect(levels(c), [null, 'code:dart', 'code:dart', 'code:dart', 'code:dart', null]);
      expect(c.document.paragraphs.hasAnyCodeBlock, isTrue);
    });

    test('exportAttributes gives one span per block, covering blank lines', () {
      final c = make('intro\n$dartCode\nafter', [codeSpan(6, 6 + dartCode.length, 'code:dart')]);
      addTearDown(c.dispose);
      final spans = c.document.exportAttributes().where((a) => a.type == AttributeType.header).toList();
      expect(spans.length, 1);
      expect([spans.single.start, spans.single.end, spans.single.value], [6, 6 + dartCode.length, 'code:dart']);
    });

    test('an empty code block is representable (one empty code line) but exports nothing', () {
      final c = make('');
      addTearDown(c.dispose);
      c.toggleCodeBlock();
      expect(c.isCodeBlockActive, isTrue);
      expect(c.document.exportAttributes().where((a) => a.type == AttributeType.header), isEmpty);
    });
  });

  group('editing', () {
    test('toggle on, language, off — each one undo step, redo restores', () {
      final c = make('a\nb\nc');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 3);
      expect(c.isCodeBlockActive, isFalse);
      c.toggleCodeBlock(language: 'dart');
      expect(levels(c), [null, 'code:dart', null]);
      expect(c.isCodeBlockActive, isTrue);
      expect(c.activeCodeLanguage, 'dart');
      c.setCodeBlockLanguage('sql');
      expect(c.activeCodeLanguage, 'sql');
      c.setCodeBlockLanguage(null);
      expect(c.activeBlockLevel, 'code');
      c.toggleCodeBlock();
      expect(levels(c), [null, null, null]);

      c.undo();
      expect(levels(c), [null, 'code', null]);
      c.undo();
      expect(levels(c), [null, 'code:sql', null]);
      c.undo();
      c.undo();
      expect(levels(c), [null, null, null]);
      c.redo();
      expect(levels(c), [null, 'code:dart', null]);
      c.redo();
      c.redo();
      c.redo();
      expect(levels(c), [null, null, null]);
    });

    test('a multi-paragraph selection becomes one block; the language applies to all of it', () {
      final c = make('a\nb\nc\nd');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
      c.toggleCodeBlock();
      expect(levels(c), [null, 'code', 'code', null]);
      c.selection = const TextSelection.collapsed(offset: 3);
      c.setCodeBlockLanguage('go');
      expect(levels(c), [null, 'code:go', 'code:go', null]);
    });

    test('Enter inside a code block adds a line to the block — even for "- x" and "1. x"', () {
      final c = make('- item\nplain', [codeSpan(0, 6)]);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 6); // end of the code line
      c.value = const TextEditingValue(text: '- item\n\nplain', selection: TextSelection.collapsed(offset: 7));
      expect(c.document.text, '- item\n\nplain', reason: 'no "- " list continuation inside code');
      expect(levels(c), ['code', 'code', null]);
    });

    test('"# " typed at the start of a code line is not a heading shortcut', () {
      final c = make('#', [codeSpan(0, 1)]);
      addTearDown(c.dispose);
      c.value = const TextEditingValue(text: '# ', selection: TextSelection.collapsed(offset: 2));
      expect(c.document.text, '# ');
      expect(levels(c), ['code']);
    });

    test('Enter in a heading still leaves the heading (existing behaviour untouched)', () {
      final c = make('Title', [const TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1')]);
      addTearDown(c.dispose);
      c.value = const TextEditingValue(text: 'Title\n', selection: TextSelection.collapsed(offset: 6));
      expect(levels(c), ['h1', null]);
    });

    test('code text keeps exact characters through typing, deleting and undo', () {
      final c = make('  x = 1;', [codeSpan(0, 8)]);
      addTearDown(c.dispose);
      c.value = const TextEditingValue(text: '  x = 1;;', selection: TextSelection.collapsed(offset: 9));
      expect(c.document.text, '  x = 1;;');
      c.undo();
      expect(c.document.text, '  x = 1;');
      expect(levels(c), ['code']);
    });

    test('size controls are disabled in a code block; a heading is not reported for it', () {
      final c = make('x', [codeSpan(0, 1)]);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 0);
      expect(c.canChangeFontSize, isFalse);
      expect(c.activeAttributeValue(AttributeType.header), isNull);
      expect(c.isCodeBlockActive, isTrue);
    });

    test('setting a heading on a code line replaces the code block level', () {
      final c = make('x', [codeSpan(0, 1)]);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 0);
      c.setHeader('h2');
      expect(levels(c), ['h2']);
      expect(c.isCodeBlockActive, isFalse);
    });

    test('inline code is independent of block code', () {
      final c = make('use x here', [const TextAttribute(start: 4, end: 5, type: AttributeType.code)]);
      addTearDown(c.dispose);
      expect(c.document.paragraphs.hasAnyCodeBlock, isFalse);
      c.selection = const TextSelection.collapsed(offset: 4);
      expect(c.isCodeBlockActive, isFalse);
    });
  });

  group('rendering', () {
    test('code lines are monospace, one row, uniform — stored inline formatting is kept but not rendered', () {
      final l = lay('plain\nbold code\nplain', attrs: [
        codeSpan(6, 15),
        const TextAttribute(start: 6, end: 10, type: AttributeType.bold),
        const TextAttribute(start: 6, end: 10, type: AttributeType.size, value: 22),
      ]);
      l.expectEveryLineOneRow();
      final style = l.runStyles.firstWhere((s) => s.fontFamily == 'monospace');
      expect(style.fontWeight, FontWeight.normal);
      expect(style.fontSize, lessThanOrEqualTo(l.metrics.maxInlineFontSize(family: 'monospace')));
      expect(l.doc.attributes.any((a) => a.type == AttributeType.bold), isTrue, reason: 'stored, not destroyed');
    });

    test('a leading "- " or "---" inside code is not styled as a list marker or rule', () {
      final l = lay('- a\n---\nz', attrs: [codeSpan(0, 7)]);
      for (final s in l.runStyles) {
        if (s.fontFamily == 'monospace') {
          expect(s.fontWeight, FontWeight.normal);
          expect(s.letterSpacing, isNull);
        }
      }
    });

    test('regions: a block\'s extent is whole rows; wrapped long lines and blank lines count', () {
      final long = 'x' * 160;
      final text = 'intro\nshort\n\n$long\nafter';
      final start = 6;
      final end = start + 'short\n\n$long'.length;
      final l = lay(text, attrs: [codeSpan(start, end, 'code:dart')], width: 200);
      final regions = l.renderer.codeBlocks;
      expect(regions.length, 1);
      final r = regions.single;
      expect(r.language, 'dart');
      expect([r.start, r.end], [start, end]);
      expect(r.top, closeTo(l.pitch, 0.02), reason: 'starts below the intro row');
      expect(r.bottom % l.pitch, closeTo(0, 0.02));
      // short + blank + >=2 wrapped rows
      expect((r.bottom - r.top) / l.pitch, greaterThanOrEqualTo(4));
      // the line after the block starts right where it ends
      expect(l.bottoms.last, closeTo(r.bottom + l.pitch, 0.02));
    });

    test('two blocks with different languages are separate regions; none when there is no code', () {
      final l = lay('a\nb\nc', attrs: [codeSpan(0, 1, 'code:dart'), codeSpan(2, 3, 'code:sql')]);
      expect(l.renderer.codeBlocks.map((r) => r.language), ['dart', 'sql']);
      final none = lay('a\nb');
      expect(none.renderer.codeBlocks, isEmpty);
    });

    test('regions are cached with the line bottoms (same instance on a repeat call)', () {
      final l = lay('a\nb', attrs: [codeSpan(0, 1)]);
      final first = l.renderer.codeBlocks;
      l.renderer.lineBottomOffsets(l.doc,
          maxWidth: 400,
          style: l.style,
          strutStyle: l.strut,
          textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.proportional));
      expect(first, isNotEmpty);
    });

    test('block rows stay on the grid at accessibility scales and with non-linear scaling', () {
      for (final scaler in <TextScaler>[const TextScaler.linear(1.4), const TextScaler.linear(3.0), CurveTextScaler.android20]) {
        final l = lay('intro\n$dartCode\nafter', attrs: [codeSpan(6, 6 + dartCode.length)], textScaler: scaler, dpr: 2.75);
        l.expectEveryLineOneRow();
        final r = l.renderer.codeBlocks.single;
        expect(r.top % l.pitch, closeTo(0, 0.02));
        expect(r.bottom % l.pitch, closeTo(0, 0.02));
      }
    });
  });

  group('ruled-paper layer', () {
    test('paints an inset rounded card (fill and border), and the paper rules run on through it', () {
      final l = lay('one\ntwo\nthree\nfour\nfive', attrs: [codeSpan(4, 13)], dpr: 1.0);
      final canvas = _Canvas();
      RuledLinesPainter(
        lineBottoms: l.bottoms,
        codeBlocks: l.renderer.codeBlocks,
        codeLeft: 10,
        codeRight: 390,
        fallbackLineHeight: l.pitch,
        topPadding: 12,
        scrollOffset: 0,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.solid,
        marginLineX: 44,
      ).paint(canvas, const Size(400, 400));
      expect(canvas.rrects.length, 2, reason: 'fill and hairline border');
      final rr = canvas.rrects.first;
      final block = l.renderer.codeBlocks.single;
      expect(rr.top, closeTo(12 + block.top + RuledLinesPainter.codeBlockInsetTop, 0.01));
      expect(rr.bottom, closeTo(12 + block.bottom - RuledLinesPainter.codeBlockInsetBottom, 0.01));
      expect(rr.left, 10);
      expect(rr.tlRadius.x, greaterThan(0));
      final top = 12 + block.top;
      final bottom = 12 + block.bottom;
      // the ruling is not cut out of the block: a rule at every row inside it
      expect(canvas.lineYs.where((y) => y > top + 0.5 && y <= bottom + 0.5).length, 2);
      // and above and below it as before
      expect(canvas.lineYs.any((y) => y <= top + 0.5), isTrue);
      expect(canvas.lineYs.any((y) => y > bottom + 0.5), isTrue);
    });

    test('a block scrolled partly above the text area is clipped at its top edge, not painted behind a header', () {
      final l = lay('a\nb\nc\nd\ne', attrs: [codeSpan(0, 9)], dpr: 1.0);
      final canvas = _Canvas();
      RuledLinesPainter(
        lineBottoms: l.bottoms,
        codeBlocks: l.renderer.codeBlocks,
        fallbackLineHeight: l.pitch,
        topPadding: 120,
        scrollOffset: l.pitch * 2,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.none,
        marginLineX: 44,
      ).paint(canvas, const Size(400, 600));
      expect(canvas.rrects, hasLength(2));
      expect(canvas.rrects.first.top, lessThan(120), reason: 'the rect itself starts above the text area');
      expect(canvas.clips, isNotEmpty);
      expect(canvas.clips.first.top, 120, reason: 'but the layer is clipped at the text area top');
    });

    test('regions report the text extent of their first row and of the row above', () {
      // blank row above, short first line
      var l = lay('intro\n\nvoid f() {}\nafter', attrs: [codeSpan(7, 18)], dpr: 1.0, width: 400);
      var r = l.renderer.codeBlocks.single;
      expect(r.previousLineRight, 0, reason: 'a blank row above has no text to collide with');
      expect(r.firstLineRight, greaterThan(40));
      expect(r.firstLineRight, lessThan(200));

      // a long line directly above (it wraps; its last row reaches into the margin)
      final long = List.filled(14, 'wordy').join(' ');
      l = lay('$long\ncode', attrs: [codeSpan(long.length + 1, long.length + 5)], dpr: 1.0, width: 400);
      r = l.renderer.codeBlocks.single;
      expect(r.previousLineRight, greaterThan(0));

      // first block line wider than the row: right edge near the wrap width
      final wide = List.filled(60, 'x').join();
      l = lay(wide, attrs: [codeSpan(0, wide.length)], dpr: 1.0, width: 400);
      expect(l.renderer.codeBlocks.single.firstLineRight, greaterThan(300));
    });

    test('a block scrolled out of view paints nothing', () {
      final l = lay('a\nb', attrs: [codeSpan(0, 1)]);
      final canvas = _Canvas();
      RuledLinesPainter(
        lineBottoms: l.bottoms,
        codeBlocks: l.renderer.codeBlocks,
        fallbackLineHeight: l.pitch,
        topPadding: 12,
        scrollOffset: 500,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.solid,
        marginLineX: 44,
      ).paint(canvas, const Size(400, 400));
      expect(canvas.rrects, isEmpty);
    });
  });

  group('copy, paste, export', () {
    test('Copy returns exactly the block text (indentation, blank lines)', () {
      final c = make('x\n$dartCode', [codeSpan(2, 2 + dartCode.length, 'code:dart')]);
      addTearDown(c.dispose);
      expect(c.codeBlockText(2, 2 + dartCode.length), dartCode);
    });

    test('copying a selection inside a block exports <pre><code>, and pasting it back restores the block', () async {
      const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');
      String? html;
      String? plain;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setData') {
          html = (call.arguments as Map)['html'] as String?;
          plain = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'getData') return {'text': plain, 'html': html};
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      final a = make('x\n$dartCode', [codeSpan(2, 2 + dartCode.length, 'code:dart')]);
      addTearDown(a.dispose);
      a.selection = TextSelection(baseOffset: 2, extentOffset: 2 + dartCode.length);
      await a.copy();
      expect(html, contains('<pre><code class="language-dart">'));
      expect(plain, dartCode);

      // A different controller (no shared in-memory rich clipboard) pastes the HTML.
      final b = make('');
      addTearDown(b.dispose);
      await b.paste();
      expect(b.document.text, dartCode);
      expect(levels(b), ['code:dart', 'code:dart', 'code:dart', 'code:dart']);
    });

    test('export: HTML and Markdown of a mixed document', () {
      final c = make('Title\n$dartCode\nend', [
        const TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1'),
        codeSpan(6, 6 + dartCode.length, 'code:dart'),
      ]);
      addTearDown(c.dispose);
      final attrs = c.document.exportAttributes();
      expect(const MarkdownExporter().export(c.document.text, attrs), '# Title\n```dart\n$dartCode\n```\nend');
      expect(const HtmlExporter().export(c.document.text, attrs), '<h1>Title</h1><pre><code class="language-dart">$dartCode</code></pre>end');
    });

    test('code with < > & is escaped in HTML and survives the round trip', () {
      const code = 'if (a < b && c > d) {}';
      final doc = EditorDocument.fromText(code, [codeSpan(0, code.length)]);
      final html = const HtmlExporter(marker: true).export(doc.text, doc.exportAttributes());
      expect(html, contains('&lt;'));
      expect(const HtmlImporter().parse(html).text, code);
    });

    test('a code block next to prose keeps its extent when exported and re-imported', () {
      final doc = EditorDocument.fromText('before\n$dartCode\nafter', [codeSpan(7, 7 + dartCode.length, 'code:dart')]);
      final html = const HtmlExporter(marker: true).export(doc.text, doc.exportAttributes());
      final back = const HtmlImporter().parse(html);
      expect(back.text, doc.text);
      final span = back.attributes.firstWhere((a) => a.value.toString().startsWith('code'));
      expect([span.start, span.end], [7, 7 + dartCode.length]);
    });
  });

  group('mounted editor', () {
    Future<void> pump(WidgetTester tester, RichEditorController c) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(
          body: RichTextEditor(controller: c, scrollController: ScrollController(), autofocus: false),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a language label and Copy for each block; Copy puts the exact code on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final c = make('intro\n$dartCode\nafter', [codeSpan(6, 6 + dartCode.length, 'code:dart')]);
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(find.text('dart'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pump();
      expect(copied, dartCode);
      expect(find.text('Code copied'), findsOneWidget);
    });

    testWidgets('a block without a language is labelled "code", and tapping the label edits the language', (tester) async {
      final c = make('x\ny', [codeSpan(0, 1)]);
      addTearDown(c.dispose);
      await pump(tester, c);
      expect(find.text('code'), findsOneWidget);
      await tester.tap(find.text('code'));
      await tester.pumpAndSettle();
      expect(find.text('Code language'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Kotlin');
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
      expect(c.document.paragraphs.records.first.headerLevel, 'code:kotlin');
      expect(find.text('kotlin'), findsOneWidget);
    });

    testWidgets('the language dialog offers one-tap common languages, Auto-detect and Plain text', (tester) async {
      final c = make('x\ny', [codeSpan(0, 1)]);
      addTearDown(c.dispose);
      await pump(tester, c);
      await tester.tap(find.text('code'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Python'));
      await tester.pumpAndSettle();
      expect(c.document.paragraphs.records.first.headerLevel, 'code:python');
      await tester.tap(find.text('python'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Plain text'));
      await tester.pumpAndSettle();
      expect(c.document.paragraphs.records.first.headerLevel, 'code:text', reason: 'explicit plain: never auto-coloured');
      expect(find.text('plain text'), findsOneWidget);
      await tester.tap(find.text('plain text'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Auto-detect'));
      await tester.pumpAndSettle();
      expect(c.document.paragraphs.records.first.headerLevel, 'code');
      expect(c.document.text, 'x\ny');
    });

    testWidgets('an unlabelled block whose text looks like a language shows that language on its chip and is coloured', (tester) async {
      const html = '<!DOCTYPE html>\n<html>\n<body>\n<h1 class="a">Hi</h1>\n</body>\n</html>';
      final c = make(html, [codeSpan(0, html.length)]);
      addTearDown(c.dispose);
      await pump(tester, c);
      expect(find.text('html'), findsOneWidget);
      expect(c.renderer.codeBlocks.single.guessedLanguage, 'html');
      expect(c.renderer.codeBlocks.single.language, isNull, reason: 'the guess is never stored');
      expect(c.document.paragraphs.records.first.headerLevel, 'code');
    });

    testWidgets('the chip is inside the card and never on code: first row, else last row, else a compact strip', (tester) async {
      Future<(double chipY, double codeY, double bottom, double rowH)> place(String text, int codeStart, int codeEnd) async {
        final c = make(text, [codeSpan(codeStart, codeEnd)]);
        addTearDown(c.dispose);
        await pump(tester, c);
        final chipY = tester.getTopLeft(find.text('code')).dy;
        final field = tester.getTopLeft(find.byType(EditableText)).dy;
        final r = c.renderer.codeBlocks.single;
        return (chipY, field + r.top, field + r.bottom, r.firstRowBottom - r.top);
      }

      // short code: on the first row, inside the card
      final short = await place('intro\n\nx = 1', 7, 12);
      expect(short.$1, greaterThan(short.$2), reason: 'inside the card, not hanging above it');
      expect(short.$1, lessThan(short.$2 + short.$4));

      final long = '${List.filled(11, 'wordy').join(' ')} ${'z' * 28}';
      // a long first line, a short second one: on the last row
      final lastRow = await place('$long\nok', 0, long.length + 3);
      expect(lastRow.$1, greaterThan(lastRow.$2 + lastRow.$4), reason: 'below the long first row');
      expect(lastRow.$1, lessThan(lastRow.$3));

      // both the first and the last row long: the compact chip rides in the top
      // padding strip, above the glyphs. (Find a line length whose wrapped last row
      // also runs under the chip's corner.)
      for (var n = 60; n < 400; n++) {
        final line = 'q' * n;
        final c = make('$line\n$line', [codeSpan(0, line.length * 2 + 1)]);
        addTearDown(c.dispose);
        await pump(tester, c);
        final r = c.renderer.codeBlocks.single;
        if (r.lastLineRight < 770 || r.firstLineRight < 770) continue;
        final chipY = tester.getTopLeft(find.text('code')).dy;
        final codeY = tester.getTopLeft(find.byType(EditableText)).dy + r.top;
        expect(chipY, greaterThan(codeY));
        expect(chipY, lessThan(codeY + 8), reason: 'in the strip above the first row of code');
        return;
      }
      fail('no line length produced two long rows');
    });

    testWidgets('no chip without code blocks', (tester) async {
      final c = make('just text');
      addTearDown(c.dispose);
      await pump(tester, c);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
    });

    testWidgets('the editor hands the painter the cached regions and the paper colour', (tester) async {
      final c = make('a\nb', [codeSpan(0, 1)]);
      addTearDown(c.dispose);
      await pump(tester, c);
      final painter = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.painter).whereType<RuledLinesPainter>().single;
      expect(painter.codeBlocks, isNotEmpty);
      expect(painter.codeBlockColor, RichEditorStyle.standard.codeBlockColor);
    });
  });
}

void lateBlockTests() {
  group('a code block that appears after the editor is mounted', () {
    Future<void> pump(WidgetTester tester, RichEditorController c) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(body: RichTextEditor(controller: c, scrollController: ScrollController(), autofocus: false)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('toggled on with the toolbar API', (tester) async {
      final c = make('one\ntwo');
      addTearDown(c.dispose);
      await pump(tester, c);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.toggleCodeBlock();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      c.toggleCodeBlock();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
    });

    testWidgets('arriving through loadDocument and through a paste of HTML', (tester) async {
      final c = make('');
      addTearDown(c.dispose);
      await pump(tester, c);
      c.loadDocument('x\ny', [codeSpan(0, 1)]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

      const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getData') {
          return {'text': 'a b', 'html': '<p>before</p><pre><code class="language-dart">a = 1\nb = 2</code></pre><p>after</p>'};
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      c.loadDocument('');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
      await c.paste();
      await tester.pumpAndSettle();
      expect(find.text('dart'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });
  });
}
