// The scoped Markdown subset, inline level: emphasis flanking, escapes,
// autolinks, and the checklist of constructs the importer is meant to handle.
// This is deliberately not full CommonMark.
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/import/markdown_importer.dart';

const md = MarkdownImporter();

List<String> spans(String source, AttributeType type) {
  final r = md.parse(source);
  return [for (final a in r.attributes.where((a) => a.type == type)) r.text.substring(a.start, a.end)];
}

void main() {
  group('emphasis needs flanking text', () {
    test('arithmetic and spaced asterisks are not emphasis, and keep their characters', () {
      final r = md.parse('2 * 3 * 4 = 24');
      expect(r.text, '2 * 3 * 4 = 24');
      expect(r.attributes, isEmpty);
    });

    test('snake_case_names are not italic; _word_ still is', () {
      expect(md.parse('call my_func_name now').text, 'call my_func_name now');
      expect(md.parse('call my_func_name now').attributes, isEmpty);
      expect(spans('an _emphasised_ word', AttributeType.italic), ['emphasised']);
    });

    test('ordinary emphasis is unchanged', () {
      expect(spans('**bold** and *it* and ~~gone~~ and `code`', AttributeType.bold), ['bold']);
      expect(spans('**bold** and *it* and ~~gone~~ and `code`', AttributeType.italic), ['it']);
      expect(spans('**bold** and *it* and ~~gone~~ and `code`', AttributeType.strikethrough), ['gone']);
      expect(spans('**bold** and *it* and ~~gone~~ and `code`', AttributeType.code), ['code']);
      expect(spans('***both***', AttributeType.bold), ['both']);
      expect(spans('***both***', AttributeType.italic), ['both']);
    });

    test('inline code may contain spaces and operators', () {
      expect(spans('use `a * b` here', AttributeType.code), ['a * b']);
    });
  });

  group('escapes', () {
    test('a backslash makes the marker literal and disappears itself', () {
      final r = md.parse(r'\*not bold\* and \_x\_');
      expect(r.text, '*not bold* and _x_');
      expect(r.attributes, isEmpty);
    });

    test('an escaped bracket does not start a link; a lone backslash stays', () {
      expect(md.parse(r'\[a](b)').text, '[a](b)');
      expect(md.parse(r'C:\path\file').text, r'C:\path\file');
    });
  });

  group('autolinks', () {
    test('<https://…> becomes a link without the brackets', () {
      final r = md.parse('see <https://kenresoft.com/docs> now');
      expect(r.text, 'see https://kenresoft.com/docs now');
      final link = r.attributes.single;
      expect(link.type, AttributeType.link);
      expect(link.value, 'https://kenresoft.com/docs');
      expect(r.text.substring(link.start, link.end), 'https://kenresoft.com/docs');
    });

    test('<email> becomes a mailto link; other schemes and plain angle text are left alone', () {
      final mail = md.parse('<me@kenresoft.com>');
      expect(mail.text, 'me@kenresoft.com');
      expect(mail.attributes.single.value, 'mailto:me@kenresoft.com');
      expect(md.parse('<javascript:alert(1)>').attributes.where((a) => a.type == AttributeType.link), isEmpty);
      expect(md.parse('a <b> c').text, 'a <b> c');
    });

    test('[text](url) and a bare URL still work', () {
      expect(md.parse('[docs](https://x.dev/a)').attributes.single.value, 'https://x.dev/a');
      expect(md.parse('go to https://x.dev/a?b=1 please').attributes.single.value, 'https://x.dev/a?b=1');
    });
  });

  group('block constructs in the subset', () {
    test('H1–H3 map to h1–h3; deeper levels fold into h3', () {
      final r = md.parse('# A\n## B\n### C\n#### D');
      expect(r.attributes.map((a) => a.value), ['h1', 'h2', 'h3', 'h3']);
      expect(r.text, 'A\nB\nC\nD');
    });

    test('CRLF input behaves like LF, fences included', () {
      final r = md.parse('a\r\n\r\n# T\r\n```dart\r\nx = 1\r\n```\r\nend');
      expect(r.text, 'a\n\nT\nx = 1\nend');
      expect(r.attributes.where((a) => a.type == AttributeType.header).map((a) => a.value), ['h1', 'code:dart']);
    });

    test('an unclosed fence runs to the end of the text as one code block', () {
      final r = md.parse('before\n```js\nlet a = 1;\n\nlet b = 2;');
      expect(r.text, 'before\nlet a = 1;\n\nlet b = 2;');
      final code = r.attributes.single;
      expect(code.value, 'code:js');
      expect(r.text.substring(code.start, code.end), 'let a = 1;\n\nlet b = 2;');
    });

    test('lists, nesting, task items and quotes stay as literal text', () {
      const src = '- a\n  - nested\n1. one\n   1. sub\n- [ ] todo\n> quoted';
      expect(md.parse(src).text, src);
    });

    test('markdown syntax inside a fence is code, not formatting', () {
      final r = md.parse('```\n**not bold** # not a heading\n```');
      expect(r.text, '**not bold** # not a heading');
      expect(r.attributes.single.value, 'code');
    });
  });
}
