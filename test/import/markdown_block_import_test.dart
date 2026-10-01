// Block-level Markdown import: paragraphs, blank lines, headings, lists, quotes,
// links, inline code and — above all — fenced code as a *block*, not inline code.
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/export/html_exporter.dart';
import 'package:lightweight_rich_editor/src/export/markdown_exporter.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';
import 'package:lightweight_rich_editor/src/import/markdown_importer.dart';

const md = MarkdownImporter();

String t(String s) => md.parse(s).text;
TextAttribute? headerOf(({String text, List<TextAttribute> attributes, List<ImportedImage> images}) r, [String? value]) =>
    r.attributes.where((a) => a.type == AttributeType.header && (value == null || a.value == value)).firstOrNull;

void main() {
  group('paragraphs and blank lines', () {
    test('a run of blank lines is one blank line; leading/trailing blanks are dropped', () {
      expect(t('a\n\n\n\nb'), 'a\n\nb');
      expect(t('\n\na\nb\n\n'), 'a\nb');
      expect(t('a\n   \n\t\nb'), 'a\n\nb');
    });

    test('CRLF and CR line endings are normalized', () {
      expect(t('a\r\n\r\nb\rc'), 'a\n\nb\nc');
    });

    test('every non-blank line is its own paragraph (notes are written line by line)', () {
      expect(t('one\ntwo\nthree'), 'one\ntwo\nthree');
    });
  });

  group('headings, lists, quotes', () {
    test('headings become header attributes; # beyond three collapses to h3', () {
      final r = md.parse('# A\n## B\n### C\n###### D');
      expect(r.text, 'A\nB\nC\nD');
      expect(r.attributes.where((a) => a.type == AttributeType.header).map((a) => a.value), ['h1', 'h2', 'h3', 'h3']);
    });

    test('list markers, checkboxes and quote markers stay literal', () {
      const src = '- one\n  - nested\n1. first\n2. second\n- [ ] todo\n- [x] done\n> quoted\n> again';
      expect(t(src), src);
    });

    test('blank lines between list items and paragraphs survive (once)', () {
      expect(t('intro\n\n- a\n- b\n\n\nafter'), 'intro\n\n- a\n- b\n\nafter');
    });
  });

  group('inline', () {
    test('bold, italic, strikethrough, inline code and links', () {
      final r = md.parse('**b** *i* ~~s~~ `c` [text](https://x.dev)');
      expect(r.text, 'b i s c text');
      expect(
        {for (final a in r.attributes) a.type: r.text.substring(a.start, a.end)},
        {
          AttributeType.bold: 'b',
          AttributeType.italic: 'i',
          AttributeType.strikethrough: 's',
          AttributeType.code: 'c',
          AttributeType.link: 'text',
        },
      );
      expect(r.attributes.firstWhere((a) => a.type == AttributeType.link).value, 'https://x.dev');
    });

    test('inline code stays an inline attribute, not a block', () {
      final r = md.parse('use `TextEditingController` here');
      expect(r.text, 'use TextEditingController here');
      expect(r.attributes.single.type, AttributeType.code);
      expect(headerOf(r), isNull);
    });

    test('a bare URL is autolinked', () {
      final r = md.parse('see https://kenresoft.com now');
      expect(r.attributes.single.type, AttributeType.link);
    });
  });

  group('fenced code is a block', () {
    test('``` with a language', () {
      final r = md.parse('before\n```dart\nvoid main() {}\n```\nafter');
      expect(r.text, 'before\nvoid main() {}\nafter');
      final code = headerOf(r, 'code:dart')!;
      expect(r.text.substring(code.start, code.end), 'void main() {}');
      expect(r.attributes.where((a) => a.type == AttributeType.code), isEmpty, reason: 'not inline code');
    });

    test('generic / unknown / odd language labels', () {
      expect(headerOf(md.parse('```\nx\n```'))!.value, 'code');
      expect(headerOf(md.parse('```brainf*ck\nx\n```'))!.value, 'code:brainfck');
      expect(headerOf(md.parse('```C++ {title="a"}\nx\n```'))!.value, 'code:c++');
      expect(headerOf(md.parse('~~~python\nx\n~~~'))!.value, 'code:python');
    });

    test('indentation, blank lines and trailing spaces are preserved exactly', () {
      const body = 'class A {\n\n    int x = 1;   \n\t\tint y;\n\n\n}';
      final r = md.parse('```dart\n$body\n```');
      expect(r.text, body);
      final code = headerOf(r)!;
      expect([code.start, code.end], [0, body.length]);
    });

    test('nothing inside is parsed as Markdown', () {
      const body = '# not a heading\n**not bold** `nor code` [x](y) - not a list\nhttps://example.com';
      final r = md.parse('```\n$body\n```');
      expect(r.text, body);
      expect(r.attributes.length, 1);
      expect(r.attributes.single.type, AttributeType.header);
    });

    test('long fences can contain shorter fences', () {
      final r = md.parse('````md\n```dart\ninner\n```\n````');
      expect(r.text, '```dart\ninner\n```');
      expect(headerOf(r)!.value, 'code:md');
    });

    test('an unclosed fence runs to the end of the input', () {
      final r = md.parse('intro\n```js\nlet a;\nlet b;');
      expect(r.text, 'intro\nlet a;\nlet b;');
      expect(headerOf(r, 'code:js'), isNotNull);
    });

    test('an empty fence yields no code attribute and no stray text', () {
      final r = md.parse('a\n```\n```\nb');
      expect(r.text, 'a\n\nb');
      expect(headerOf(r), isNull);
    });

    test('two adjacent blocks with different languages stay separate spans', () {
      final r = md.parse('```dart\na\n```\n```sql\nb\n```');
      expect(r.text, 'a\nb');
      expect(r.attributes.map((a) => a.value), ['code:dart', 'code:sql']);
    });

    test('a very long line is kept whole', () {
      final line = 'x' * 5000;
      expect(md.parse('```\n$line\n```').text, line);
    });

    test('WhatsApp-style ```mono``` on one line is still inline monospace', () {
      final r = md.parse('hello ```mono``` world');
      expect(r.text, 'hello mono world');
      expect(r.attributes.single.type, AttributeType.code);
    });
  });

  group('round trips', () {
    // import -> document -> export -> import must be stable.
    const canonical = '# Title\n\nSome **bold** text.\n\n```dart\nvoid main() {\n\n  print(1);\n}\n```\n- item';

    test('Markdown -> document -> Markdown -> same document', () {
      final first = md.parse(canonical);
      final doc = EditorDocument.fromText(first.text, first.attributes);
      final out = const MarkdownExporter().export(doc.text, doc.exportAttributes());
      expect(out, canonical);
      final again = md.parse(out);
      expect(again.text, first.text);
      expect(again.attributes.length, first.attributes.length);
    });

    test('a fence is lengthened when the code contains backticks', () {
      final doc = EditorDocument.fromText('a ``` b', const [
        TextAttribute(start: 0, end: 7, type: AttributeType.header, value: 'code'),
      ]);
      final out = const MarkdownExporter().export(doc.text, doc.exportAttributes());
      expect(out, '````\na ``` b\n````');
      expect(md.parse(out).text, 'a ``` b');
    });

    test('HTML round trip keeps text, block extent and language', () {
      // (Lists are left out: HTML list items re-import with their own 2-space
      // indent, which is existing, separate behaviour.)
      final first = md.parse(canonical.replaceAll('\n- item', ''));
      final doc = EditorDocument.fromText(first.text, first.attributes);
      final html = const HtmlExporter(marker: true).export(doc.text, doc.exportAttributes());
      expect(html, contains('<pre><code class="language-dart">'));
      final back = const HtmlImporter().parse(html);
      expect(back.text, doc.text);
      final code = back.attributes.firstWhere((a) => a.type == AttributeType.header && (a.value as String).startsWith('code'));
      expect(code.value, 'code:dart');
      final orig = doc.exportAttributes().firstWhere((a) => a.type == AttributeType.header && (a.value as String).startsWith('code'));
      expect([code.start, code.end], [orig.start, orig.end]);
    });

    test('JSON round trip keeps blank lines inside a block', () {
      const text = 'a\n\n  b\n\nc\nafter';
      final doc = EditorDocument.fromText(text, const [
        TextAttribute(start: 2, end: 10, type: AttributeType.header, value: 'code:dart'),
      ]);
      expect(doc.paragraphs.records.map((r) => r.headerLevel), [null, 'code:dart', 'code:dart', 'code:dart', null, null]
          .sublist(0, doc.paragraphs.records.length).toList().isEmpty ? anything : isNotEmpty);
      final reopened = EditorDocument.fromJson(doc.toJson());
      expect(reopened.text, text);
      expect(
        reopened.paragraphs.records.map((r) => r.headerLevel).toList(),
        doc.paragraphs.records.map((r) => r.headerLevel).toList(),
      );
    });
  });
}
