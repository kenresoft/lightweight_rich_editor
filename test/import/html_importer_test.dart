import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';

void main() {
  const importer = HtmlImporter();

  group('HtmlImporter', () {
    test('basic tags', () {
      final result = importer.parse('<b>Bold</b> <i>Italic</i> <u>Underline</u>');
      expect(result.text, 'Bold Italic Underline');
      expect(result.attributes, hasLength(3));
      expect(result.attributes[0].type, AttributeType.bold);
      expect(result.attributes[1].type, AttributeType.italic);
      expect(result.attributes[2].type, AttributeType.underline);
    });

    test('nested tags', () {
      final result = importer.parse('<b>Bold <i>and Italic</i></b>');
      expect(result.text, 'Bold and Italic');
      expect(result.attributes, hasLength(2));
      // Bold should cover the whole text
      final bold = result.attributes.firstWhere((a) => a.type == AttributeType.bold);
      expect(bold.start, 0);
      expect(bold.end, 15);
      // Italic should cover "and Italic"
      final italic = result.attributes.firstWhere((a) => a.type == AttributeType.italic);
      expect(italic.start, 5);
      expect(italic.end, 15);
    });

    test('links', () {
      final result = importer.parse('<a href="https://example.com">Link</a>');
      expect(result.text, 'Link');
      expect(result.attributes.single.type, AttributeType.link);
      expect(result.attributes.single.value, 'https://example.com');
    });

    test('block elements and newlines', () {
      final result = importer.parse('<h1>Header</h1><p>Paragraph</p><div>Div</div>');
      expect(result.text, 'Header\nParagraph\nDiv');
      expect(result.attributes.any((a) => a.type == AttributeType.header), isTrue);
    });

    test('whitespace handling between inline elements', () {
      final result = importer.parse('<b>A</b> <b>B</b>');
      // Current implementation might return "AB" due to trim().isEmpty check
      expect(result.text, 'A B');
    });

    test('br tag', () {
      final result = importer.parse('Line 1<br>Line 2');
      expect(result.text, 'Line 1\nLine 2');
    });

    test('styled span with font-weight', () {
      final result = importer.parse('<span style="font-weight: bold;">Bold Span</span>');
      expect(result.text, 'Bold Span');
      expect(result.attributes.single.type, AttributeType.bold);
    });

    test('styled span with font-style', () {
      final result = importer.parse('<span style="font-style: italic;">Italic Span</span>');
      expect(result.text, 'Italic Span');
      expect(result.attributes.single.type, AttributeType.italic);
    });

    test('styled span with text-decoration underline', () {
      final result = importer.parse('<span style="text-decoration: underline;">Underline Span</span>');
      expect(result.text, 'Underline Span');
      expect(result.attributes.single.type, AttributeType.underline);
    });

    test('complex styled span', () {
      final result = importer.parse('<span style="font-weight: bold; font-style: italic;">Bold Italic Span</span>');
      expect(result.text, 'Bold Italic Span');
      expect(result.attributes, hasLength(2));
      expect(result.attributes.any((a) => a.type == AttributeType.bold), isTrue);
      expect(result.attributes.any((a) => a.type == AttributeType.italic), isTrue);
    });

    test('text-align style produces an AttributeType.align attribute', () {
      final result = importer.parse('<div style="text-align: center;">Centered</div>');
      expect(result.text, 'Centered');
      expect(result.attributes.single.type, AttributeType.align);
      expect(result.attributes.single.value, 'center');
    });

    test('an unrecognized text-align value (justify) is not imported', () {
      final result = importer.parse('<div style="text-align: justify;">Text</div>');
      expect(result.text, 'Text');
      expect(result.attributes.where((a) => a.type == AttributeType.align), isEmpty);
    });

    test('dir="rtl" attribute produces an AttributeType.textDirection attribute', () {
      final result = importer.parse('<div dir="rtl">Text</div>');
      expect(result.text, 'Text');
      expect(result.attributes.single.type, AttributeType.textDirection);
      expect(result.attributes.single.value, 'rtl');
    });

    test('an unrecognized dir value is not imported', () {
      final result = importer.parse('<div dir="auto">Text</div>');
      expect(result.text, 'Text');
      expect(result.attributes.where((a) => a.type == AttributeType.textDirection), isEmpty);
    });
  });

  group('HtmlImporter — lists', () {
    test('a tightly-written bullet list has no blank lines between items', () {
      final result = importer.parse('<ul><li>Item one</li><li>Item two</li></ul>');
      expect(result.text, '  - Item one\n  - Item two');
    });

    // Regression test for a real, reported bug: real-world HTML sources
    // (a browser's "Copy" on a rendered page, Google Docs, Notion, Word)
    // pretty-print their markup with a newline + indentation between
    // sibling tags. Before this fix, each of those insignificant
    // whitespace-only text nodes between <li> siblings got written into
    // the output as a literal lone space, and — because that space
    // didn't count as "the buffer already ends with a newline" — the
    // next <li>'s own block-boundary check inserted an *additional* '\n'
    // on top of it, producing a blank-looking line between every item.
    test('a pretty-printed bullet list (newlines/indentation between <li> tags) has no blank lines between items', () {
      const html = '<ul>\n  <li>Item one</li>\n  <li>Item two</li>\n</ul>';
      final result = importer.parse(html);
      expect(result.text, '  - Item one\n  - Item two');
    });

    test('a pretty-printed ordered list has no blank lines and numbers correctly', () {
      const html = '<ol>\n  <li>First</li>\n  <li>Second</li>\n  <li>Third</li>\n</ol>';
      final result = importer.parse(html);
      expect(result.text, '  1. First\n  2. Second\n  3. Third');
    });

    // Regression test for the other half of the same reported bug: a
    // <li> whose own content is wrapped in a nested block element (very
    // common in real-world exports — Google Docs/Notion/Word HTML all
    // routinely emit `<li><p>text</p></li>` rather than a bare text
    // node) used to have its marker pushed onto its own line, orphaned,
    // with the item's actual text starting on the *next* line instead of
    // right after the marker — "bullet on one line, text under it in
    // the next line".
    test('a <li> wrapping its content in a <p> keeps the marker and text on the same line', () {
      final result = importer.parse('<ul><li><p>Item one</p></li></ul>');
      expect(result.text, '  - Item one');
    });

    test('a <li> with a doubly-nested block wrapper (<div><p>) still keeps marker and text together', () {
      final result = importer.parse('<ul><li><div><p>Item one</p></div></li></ul>');
      expect(result.text, '  - Item one');
    });

    test('only the first block child of a <li> is glued to the marker — a second one still breaks', () {
      final result = importer.parse('<ul><li><p>First</p><p>Second</p></li></ul>');
      expect(result.text, '  - First\nSecond');
    });

    test('pretty-printed paragraphs have no blank line inserted between them', () {
      const html = '<div>\n  <p>First paragraph</p>\n  <p>Second paragraph</p>\n</div>';
      final result = importer.parse(html);
      expect(result.text, 'First paragraph\nSecond paragraph');
    });

    test('whitespace between genuine inline content is still preserved', () {
      final result = importer.parse('<p>Hello <b>world</b></p>');
      expect(result.text, 'Hello world');
    });
  });
}
