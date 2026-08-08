import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/import/markdown_importer.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';

const _importer = MarkdownImporter();

void main() {
  group('MarkdownImporter — inline formatting', () {
    test('bold', () {
      final result = _importer.parse('this is **bold** text');
      expect(result.text, 'this is bold text');
      expect(result.attributes, hasLength(1));
      expect(result.attributes.single.type, AttributeType.bold);
      expect(result.text.substring(result.attributes.single.start, result.attributes.single.end), 'bold');
    });

    test('italic with asterisks', () {
      final result = _importer.parse('this is *italic* text');
      expect(result.text, 'this is italic text');
      expect(result.attributes.single.type, AttributeType.italic);
    });

    test('italic with underscores', () {
      final result = _importer.parse('this is _italic_ text');
      expect(result.text, 'this is italic text');
      expect(result.attributes.single.type, AttributeType.italic);
    });

    test('strikethrough', () {
      final result = _importer.parse('~~gone~~');
      expect(result.text, 'gone');
      expect(result.attributes.single.type, AttributeType.strikethrough);
    });

    test('inline code', () {
      final result = _importer.parse('use `code` here');
      expect(result.text, 'use code here');
      expect(result.attributes.single.type, AttributeType.code);
    });

    test('multiple non-overlapping runs on one line', () {
      final result = _importer.parse('**bold** and *italic* and `code`');
      expect(result.text, 'bold and italic and code');
      expect(result.attributes, hasLength(3));
      expect(result.attributes.map((a) => a.type).toSet(),
          {AttributeType.bold, AttributeType.italic, AttributeType.code});
    });

    test('bold with underscores', () {
      final result = _importer.parse('this is __bold__ text');
      expect(result.text, 'this is bold text');
      expect(result.attributes.single.type, AttributeType.bold);
    });

    test('nested bold and italic', () {
      final result = _importer.parse('**bold _italic_ bold**');
      expect(result.text, 'bold italic bold');
      final bold = result.attributes.firstWhere((a) => a.type == AttributeType.bold);
      final italic = result.attributes.firstWhere((a) => a.type == AttributeType.italic);
      expect(bold.start, 0);
      expect(bold.end, 16);
      expect(italic.start, 5);
      expect(italic.end, 11);
    });
  });

  group('MarkdownImporter — links', () {
    test('parses [text](url)', () {
      final result = _importer.parse('check [this site](https://example.com) out');
      expect(result.text, 'check this site out');
      expect(result.attributes.single.type, AttributeType.link);
      expect(result.attributes.single.value, 'https://example.com');
      expect(
        result.text.substring(result.attributes.single.start, result.attributes.single.end),
        'this site',
      );
    });

    test('does not parse emphasis inside link text', () {
      final result = _importer.parse('[**bold link**](https://example.com)');
      expect(result.text, '**bold link**'); // link text treated as literal, by design
      expect(result.attributes.single.type, AttributeType.link);
    });
  });

  group('MarkdownImporter — headers', () {
    test('# becomes h1', () {
      final result = _importer.parse('# Title');
      expect(result.text, 'Title');
      expect(result.attributes.single.type, AttributeType.header);
      expect(result.attributes.single.value, 'h1');
    });

    test('## becomes h2', () {
      final result = _importer.parse('## Subtitle');
      expect(result.attributes.single.value, 'h2');
    });

    test('###+ collapses to h2', () {
      final result = _importer.parse('#### Deep heading');
      expect(result.text, 'Deep heading');
      expect(result.attributes.single.value, 'h2');
    });

    test('header only applies to its own line', () {
      final result = _importer.parse('# Title\nbody text');
      expect(result.text, 'Title\nbody text');
      expect(result.attributes.single.start, 0);
      expect(result.attributes.single.end, 5); // just "Title"
    });

    test('a single # with no following space is not a header', () {
      final result = _importer.parse('#nothashtag');
      expect(result.text, '#nothashtag');
      expect(result.attributes, isEmpty);
    });
  });

  group('MarkdownImporter — multi-line documents', () {
    test('preserves line breaks and offsets attributes correctly per line', () {
      final result = _importer.parse('# Heading\n**bold** on line two');
      expect(result.text, 'Heading\nbold on line two');

      final header = result.attributes.firstWhere((a) => a.type == AttributeType.header);
      expect(header.start, 0);
      expect(header.end, 7); // "Heading"

      final bold = result.attributes.firstWhere((a) => a.type == AttributeType.bold);
      expect(result.text.substring(bold.start, bold.end), 'bold');
    });
  });

  group('MarkdownImporter — malformed/unclosed markers degrade gracefully', () {
    test('an unclosed bold marker is preserved as literal text, not dropped', () {
      final result = _importer.parse('this is **not closed');
      expect(result.text, 'this is **not closed');
      expect(result.attributes, isEmpty);
    });

    test('an odd number of markers on a line degrades the leftover to literal', () {
      final result = _importer.parse('*one* two *three');
      expect(result.text, 'one two *three');
      expect(result.attributes, hasLength(1));
      expect(result.attributes.single.type, AttributeType.italic);
    });

    test('empty-content markers are left as literal text, not consumed', () {
      // "****" has no content between the two "**" pairs to actually
      // format, so _pairMarkers drops the pair rather than creating a
      // zero-width attribute — which means those characters were never
      // claimed by a valid pair, so the final pass writes them literally
      // rather than silently eating them.
      final result = _importer.parse('before **** after');
      expect(result.text, 'before **** after');
      expect(result.attributes, isEmpty);
    });

    test('plain text with no markdown syntax passes through unchanged', () {
      final result = _importer.parse('just plain text, nothing special');
      expect(result.text, 'just plain text, nothing special');
      expect(result.attributes, isEmpty);
    });
  });
}