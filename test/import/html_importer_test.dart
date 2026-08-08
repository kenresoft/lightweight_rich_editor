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
  });
}
