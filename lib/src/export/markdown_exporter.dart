import '../models/attribute_type.dart';
import '../models/text_attribute.dart';

/// Converts plain text and [TextAttribute]s into a Markdown string.
class MarkdownExporter {
  const MarkdownExporter();

  String export(String text, List<TextAttribute> attributes) {
    if (attributes.isEmpty) return text;

    final buffer = StringBuffer();
    final sorted = List<TextAttribute>.from(attributes)
      ..sort((a, b) {
        if (a.start != b.start) return a.start.compareTo(b.start);
        return b.end.compareTo(a.end);
      });

    for (var i = 0; i < text.length; i++) {
      // Closing tags
      final closing = sorted.where((a) => a.end == i).toList().reversed;
      for (final attr in closing) {
        buffer.write(_markerFor(attr.type, isOpen: false));
      }

      // Opening tags
      final opening = sorted.where((a) => a.start == i);
      for (final attr in opening) {
        buffer.write(_markerFor(attr.type, value: attr.value, isOpen: true));
      }

      buffer.write(text[i]);
    }

    // Final closing tags
    final finalClosing = sorted.where((a) => a.end == text.length).toList().reversed;
    for (final attr in finalClosing) {
      buffer.write(_markerFor(attr.type, isOpen: false));
    }

    return buffer.toString();
  }

  String _markerFor(AttributeType type, {Object? value, required bool isOpen}) {
    switch (type) {
      case AttributeType.bold:
        return '**';
      case AttributeType.italic:
        return '*';
      case AttributeType.underline:
        // Markdown doesn't have a standard underline, using HTML tag
        return isOpen ? '<u>' : '</u>';
      case AttributeType.strikethrough:
        return '~~';
      case AttributeType.code:
        return '`';
      case AttributeType.link:
        return isOpen ? '[' : ']($value)';
      case AttributeType.header:
        if (isOpen) {
          return value == 'h1' ? '# ' : '## ';
        }
        return ''; // headers don't have closing markers in this model (line-based)
      default:
        return '';
    }
  }
}
