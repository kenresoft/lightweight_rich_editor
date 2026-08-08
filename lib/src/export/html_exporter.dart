import '../models/attribute_type.dart';
import '../models/text_attribute.dart';

/// Converts plain text and [TextAttribute]s into an HTML string for
/// copying to the system clipboard or exporting to other apps.
class HtmlExporter {
  const HtmlExporter();

  String export(String text, List<TextAttribute> attributes) {
    final buffer = StringBuffer();
    // Sort by start position, then by end position (nesting)
    final sorted = List<TextAttribute>.from(attributes)
      ..sort((a, b) {
        if (a.start != b.start) return a.start.compareTo(b.start);
        return b.end.compareTo(a.end);
      });

    for (var i = 0; i < text.length; i++) {
      // Closing tags (reverse order of opening)
      final closing = sorted.where((a) => a.end == i).toList().reversed;
      for (final attr in closing) {
        buffer.write(_tagFor(attr.type, isOpen: false));
      }

      // Opening tags
      final opening = sorted.where((a) => a.start == i);
      for (final attr in opening) {
        buffer.write(_tagFor(attr.type, value: attr.value, isOpen: true));
      }

      final char = text[i];
      if (char == '\n') {
        buffer.write('<br>');
      } else if (char == '<') {
        buffer.write('&lt;');
      } else if (char == '>') {
        buffer.write('&gt;');
      } else if (char == '&') {
        buffer.write('&amp;');
      } else {
        buffer.write(char);
      }
    }

    // Final closing tags at the very end
    final finalClosing = sorted.where((a) => a.end == text.length).toList().reversed;
    for (final attr in finalClosing) {
      buffer.write(_tagFor(attr.type, isOpen: false));
    }

    return buffer.toString();
  }

  String _tagFor(AttributeType type, {Object? value, required bool isOpen}) {
    switch (type) {
      case AttributeType.bold:
        return isOpen ? '<b>' : '</b>';
      case AttributeType.italic:
        return isOpen ? '<i>' : '</i>';
      case AttributeType.underline:
        return isOpen ? '<u>' : '</u>';
      case AttributeType.strikethrough:
        return isOpen ? '<s>' : '</s>';
      case AttributeType.code:
        return isOpen ? '<code>' : '</code>';
      case AttributeType.link:
        return isOpen ? '<a href="$value">' : '</a>';
      case AttributeType.header:
        final tag = value == 'h1' ? 'h1' : 'h2';
        return isOpen ? '<$tag>' : '</$tag>';
      default:
        return '';
    }
  }
}
