// A document must reach a fixed point: exporting and re-importing it again and
// again may not add blank lines, change headings or code blocks, or grow.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/export/html_exporter.dart';
import 'package:lightweight_rich_editor/src/export/markdown_exporter.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';
import 'package:lightweight_rich_editor/src/import/markdown_importer.dart';

import '../support/notebook_test_support.dart';

// A realistic note: title, prose with inline formatting and a link, deliberate
// blank lines, a list, a quote-style line, a heading, and two code blocks (one
// with blank lines and indentation, one labelled).
const _text = 'Title\n'
    'Intro with bold and italic and a link here.\n'
    '\n'
    'Second paragraph.\n'
    '\n'
    '\n'
    'Heading two\n'
    'Steps:\n'
    '  - one\n'
    '    - nested\n'
    '  - two\n'
    '  3. third\n'
    '  4. fourth\n'
    '> a quote\n'
    'void main() {\n'
    '\n'
    '  print(1);\n'
    '}\n'
    'after code\n'
    'x = 1\n'
    'y = 2\n'
    'end';

List<TextAttribute> _attrs() {
  int at(String s) => _text.indexOf(s);
  int endOf(String s) => at(s) + s.length;
  return [
    TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1'),
    TextAttribute(start: at('bold'), end: endOf('bold'), type: AttributeType.bold),
    TextAttribute(start: at('italic'), end: endOf('italic'), type: AttributeType.italic),
    TextAttribute(start: at('link'), end: endOf('link'), type: AttributeType.link, value: 'https://kenresoft.com'),
    TextAttribute(start: at('Heading two'), end: endOf('Heading two'), type: AttributeType.header, value: 'h2'),
    TextAttribute(start: at('void main'), end: endOf('}\n') - 1, type: AttributeType.header, value: 'code:dart'),
    TextAttribute(start: at('x = 1'), end: endOf('y = 2'), type: AttributeType.header, value: 'code'),
  ];
}

({String text, List<TextAttribute> attrs}) _htmlCycle(String text, List<TextAttribute> attrs, {required bool marker}) {
  final html = HtmlExporter(marker: marker).export(text, attrs);
  final back = const HtmlImporter().parse(html);
  return (text: back.text, attrs: EditorDocument.fromText(back.text, back.attributes).exportAttributes());
}

({String text, List<TextAttribute> attrs}) _mdCycle(String text, List<TextAttribute> attrs) {
  final md = const MarkdownExporter().export(text, attrs);
  final back = const MarkdownImporter().parse(md);
  return (text: back.text, attrs: EditorDocument.fromText(back.text, back.attributes).exportAttributes());
}

List<String?> _levels(String text, List<TextAttribute> attrs) =>
    EditorDocument.fromText(text, attrs).paragraphs.records.map((r) => r.headerLevel).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HTML', () {
    for (final marker in [true, false]) {
      test('${marker ? 'our own export (marker)' : 'plain export'}: no growth over 6 cycles, text stable once settled', () {
        var cur = (text: _text, attrs: _attrs());
        final lengths = <int>[];
        final texts = <String>[];
        for (var i = 0; i < 6; i++) {
          cur = _htmlCycle(cur.text, cur.attrs, marker: marker);
          lengths.add(cur.text.length);
          texts.add(cur.text);
        }
        // The second and later passes change nothing: a fixed point.
        expect(texts.skip(1).toSet().length, 1, reason: 'texts after cycle 1 differ: $lengths');
        expect(lengths.last, lessThanOrEqualTo(_text.length + 8 * 2), reason: 'a note may not grow by blank lines per cycle');
      });
    }

    test('marker export is lossless: same text, headings and code blocks after one cycle', () {
      final back = _htmlCycle(_text, _attrs(), marker: true);
      expect(back.text, _text);
      expect(_levels(back.text, back.attrs), _levels(_text, _attrs()));
    });

    test('code block blank lines and indentation survive every cycle', () {
      var cur = (text: _text, attrs: _attrs());
      for (var i = 0; i < 4; i++) {
        cur = _htmlCycle(cur.text, cur.attrs, marker: true);
        expect(cur.text, contains('void main() {\n\n  print(1);\n}'));
      }
    });

    test('an exported heading is never doubled into extra blank lines', () {
      var cur = (text: 'a\nTitle\nb', attrs: [TextAttribute(start: 2, end: 7, type: AttributeType.header, value: 'h1')]);
      for (var i = 0; i < 5; i++) {
        cur = _htmlCycle(cur.text, cur.attrs, marker: true);
      }
      expect(cur.text, 'a\nTitle\nb');
    });

    test('an empty document and a single blank line stay as they are', () {
      expect(_htmlCycle('', const [], marker: true).text, '');
      expect(_htmlCycle('a\n\n\nb', const [], marker: true).text, 'a\n\n\nb');
    });
  });

  group('lists and spacer <br>', () {
    test('nested items export as nested lists, flat ones as before', () {
      expect(const HtmlExporter().export('  - a\n    - b\n  - c', const []), '<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>');
      expect(const HtmlExporter().export('  - a\n  - b', const []), '<ul><li>a</li><li>b</li></ul>');
    });

    test('a numbered list that starts elsewhere keeps its first number', () {
      expect(const HtmlExporter().export('  3. x\n  4. y', const []), '<ol start="3"><li>x</li><li>y</li></ol>');
      expect(const HtmlExporter().export('  1. x', const []), '<ol><li>x</li></ol>');
    });

    test('nested lists and a numbered start re-import to the same text', () {
      const t = '  - a\n    - b\n      - c\n  - d\n  7. x\n  8. y';
      final html = const HtmlExporter(marker: true).export(t, const []);
      expect(const HtmlImporter().parse(html).text, t);
    });

    test('a spacer <br> right after a block is its blank line, not a second one', () {
      expect(const HtmlImporter().parse('<p>a</p><br><p>b</p>').text, 'a\n\nb');
      expect(const HtmlImporter().parse('<ul><li>x</li></ul><br>after').text, '  - x\n\nafter');
    });

    test('deliberate runs of <br> still count beyond the first', () {
      expect(const HtmlImporter().parse('<p>a</p><br><br><p>b</p>').text, 'a\n\n\nb');
      expect(const HtmlImporter().parse('a<br><br>b').text, 'a\n\nb');
    });
  });

  group('Markdown', () {
    test('settles after the first cycle and never grows (scoped subset)', () {
      var cur = (text: _text, attrs: _attrs());
      final texts = <String>[];
      for (var i = 0; i < 6; i++) {
        cur = _mdCycle(cur.text, cur.attrs);
        texts.add(cur.text);
      }
      expect(texts.skip(1).toSet().length, 1, reason: 'lengths: ${texts.map((t) => t.length)}');
      expect(texts.last.length, lessThanOrEqualTo(_text.length + 16));
    });

    test('fenced code, its language and its blank lines survive repeated cycles', () {
      var cur = (text: _text, attrs: _attrs());
      for (var i = 0; i < 4; i++) {
        cur = _mdCycle(cur.text, cur.attrs);
      }
      expect(cur.text, contains('void main() {\n\n  print(1);\n}'));
      expect(_levels(cur.text, cur.attrs), contains('code:dart'));
    });
  });

  group('copy / paste through the clipboard, repeatedly', () {
    test('copying all and pasting over everything never grows the note', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      final c = RichEditorController(text: _text, theme: notebookTheme, initialAttributes: _attrs());
      addTearDown(c.dispose);
      final sizes = <int>[];
      for (var i = 0; i < 4; i++) {
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.document.length);
        await c.copy();
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.document.length);
        await c.paste();
        sizes.add(c.document.length);
      }
      expect(sizes.toSet().length, 1, reason: 'sizes: $sizes');
      expect(c.document.text, _text);
      expect(_levels(c.document.text, c.document.exportAttributes()), _levels(_text, _attrs()));
    });
  });
}
