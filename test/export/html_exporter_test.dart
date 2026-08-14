import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/export/html_exporter.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

void main() {
  const exporter = HtmlExporter();

  group('HtmlExporter', () {
    test('basic attributes', () {
      final text = 'Bold and Italic';
      final attributes = [
        TextAttribute(start: 0, end: 4, type: AttributeType.bold),
        TextAttribute(start: 9, end: 15, type: AttributeType.italic),
      ];
      final result = exporter.export(text, attributes);
      expect(result, '<b>Bold</b> and <i>Italic</i>');
    });

    test('nested attributes', () {
      final text = 'Bold and Italic';
      final attributes = [
        TextAttribute(start: 0, end: 15, type: AttributeType.bold),
        TextAttribute(start: 9, end: 15, type: AttributeType.italic),
      ];
      final result = exporter.export(text, attributes);
      expect(result, '<b>Bold and <i>Italic</i></b>');
    });

    test('links', () {
      final text = 'Click here';
      final attributes = [
        TextAttribute(start: 6, end: 10, type: AttributeType.link, value: 'https://example.com'),
      ];
      final result = exporter.export(text, attributes);
      expect(result, 'Click <a href="https://example.com">here</a>');
    });

    test('special characters escaping', () {
      final text = 'A < B & C > D';
      final result = exporter.export(text, []);
      expect(result, 'A &lt; B &amp; C &gt; D');
    });

    test('newlines to br', () {
      final text = 'Line 1\nLine 2';
      final result = exporter.export(text, []);
      expect(result, 'Line 1<br>Line 2');
    });

    test('alignment wraps the paragraph in a styled div', () {
      final text = 'Centered text';
      final attributes = [
        TextAttribute(start: 0, end: text.length, type: AttributeType.align, value: 'center'),
      ];
      final result = exporter.export(text, attributes);
      expect(result, '<div style="text-align:center">Centered text</div>');
    });

    test('text direction wraps the paragraph in a dir="rtl" div', () {
      final text = 'טקסט בעברית';
      final attributes = [
        TextAttribute(start: 0, end: text.length, type: AttributeType.textDirection, value: 'rtl'),
      ];
      final result = exporter.export(text, attributes);
      expect(result, '<div dir="rtl">$text</div>');
    });

    test('an unaligned paragraph is unaffected — no attribute, no wrapping', () {
      final result = exporter.export('Plain text', []);
      expect(result, 'Plain text');
    });
  });
}
