import '../models/attribute_type.dart';
import '../models/code_block.dart';
import '../models/image_block.dart';
import '../models/text_attribute.dart';

/// Converts plain text and [TextAttribute]s into a Markdown string.
///
/// Paragraph alignment and text direction have no CommonMark equivalent
/// and are not exported; they still round-trip via JSON and HTML.
class MarkdownExporter {
  const MarkdownExporter();

  String export(String text, List<TextAttribute> attributes) {
    if (text.isEmpty) return '';
    if (attributes.isEmpty) return text;

    bool isCodeSpan(TextAttribute a) =>
        a.type == AttributeType.header && isCodeBlockLevel(a.value as String?);
    final codeSpans = attributes.where(isCodeSpan).toList();
    bool isImageSpan(TextAttribute a) => a.type == AttributeType.header && isImageLevel(a.value as String?);
    final imageSpans = attributes.where(isImageSpan).toList();
    final sorted = attributes.where((a) => !isCodeSpan(a) && !isImageSpan(a)).toList()
      ..sort((a, b) {
        if (a.start != b.start) return a.start.compareTo(b.start);
        return b.end.compareTo(a.end);
      });

    final buffer = StringBuffer();
    var pos = 0;
    var isFirstParagraph = true;

    while (true) {
      final nextNewline = text.indexOf('\n', pos);
      final paragraphEnd = nextNewline == -1 ? text.length : nextNewline;

      TextAttribute? image;
      for (final a in imageSpans) {
        if (a.start <= pos && a.end >= pos && a.end > a.start) {
          image = a;
          break;
        }
      }
      if (image != null) {
        // The picture itself lives in the app's image store, not in the text.
        if (!isFirstParagraph) buffer.write('\n');
        buffer.write('![image](rich-image:${imageIdOf(image.value as String?) ?? ''})');
        isFirstParagraph = false;
        final imageEnd = image.end > text.length ? text.length : image.end;
        if (imageEnd >= text.length) break;
        pos = imageEnd + 1;
        continue;
      }

      TextAttribute? code;
      for (final a in codeSpans) {
        if (a.start <= pos && a.end >= pos && a.end > a.start) {
          code = a;
          break;
        }
      }
      if (code != null) {
        // Fenced block: the fence is longer than any backtick run inside it.
        final codeEnd = code.end > text.length ? text.length : code.end;
        final body = text.substring(pos, codeEnd);
        var fenceLen = 3;
        for (final m in RegExp('`+').allMatches(body)) {
          if (m.group(0)!.length >= fenceLen) fenceLen = m.group(0)!.length + 1;
        }
        final fence = '`' * fenceLen;
        if (!isFirstParagraph) buffer.write('\n');
        buffer.write('$fence${codeBlockLanguage(code.value as String?) ?? ''}\n$body\n$fence');
        isFirstParagraph = false;
        if (codeEnd >= text.length) break;
        pos = codeEnd + 1;
        continue;
      }

      if (!isFirstParagraph) buffer.write('\n');
      buffer.write(_renderInline(text, pos, paragraphEnd, sorted));

      isFirstParagraph = false;
      if (nextNewline == -1) break;
      pos = nextNewline + 1;
    }

    return buffer.toString();
  }

  // Renders one paragraph's inline content. Attributes already active
  // when the window starts are opened up front; ones still open at the
  // end are force-closed and reopened by the next paragraph's call.
  String _renderInline(String text, int start, int end, List<TextAttribute> sorted) {
    if (start >= end) return '';
    final buffer = StringBuffer();

    final activeAtStart = sorted.where((a) => a.start < start && a.end > start);
    for (final attr in activeAtStart) {
      buffer.write(_markerFor(attr.type, value: attr.value, isOpen: true));
    }

    for (var i = start; i < end; i++) {
      final closing = sorted.where((a) => a.end == i && a.start < end && a.end > start).toList().reversed;
      for (final attr in closing) {
        buffer.write(_markerFor(attr.type, isOpen: false));
      }
      final opening = sorted.where((a) => a.start == i && a.start >= start);
      for (final attr in opening) {
        buffer.write(_markerFor(attr.type, value: attr.value, isOpen: true));
      }
      buffer.write(text[i]);
    }

    final stillOpenAtEnd = sorted.where((a) => a.start < end && a.end >= end && a.start < a.end).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    for (final attr in stillOpenAtEnd) {
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
          if (value == 'h1') return '# ';
          if (value == 'h2') return '## ';
          return '### ';
        }
        return ''; // headers don't have closing markers in this model (line-based)
      default:
        return '';
    }
  }
}