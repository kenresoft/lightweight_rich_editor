import '../models/attribute_type.dart';
import '../models/text_attribute.dart';

/// Converts plain text and [TextAttribute]s into a Markdown string.
///
/// Closes and reopens inline markers at each paragraph boundary, rather
/// than letting one span's markers straddle a `'\n'` — matters only for
/// the narrow case of a bold/italic/etc. span crossing a paragraph
/// break (most formatting stays within one paragraph and is unaffected
/// either way). Same windowed-attribute approach as `HtmlExporter`
/// (`activeAtStart`/`stillOpenAtEnd`), adapted for Markdown's symmetric
/// marker syntax (`**` opens and closes bold, unlike HTML's distinct
/// `<b>`/`</b>`) — `_markerFor` already returns the same string for
/// both, so no other change was needed to reuse the pattern.
///
/// `AttributeType.align`/`AttributeType.textDirection` are deliberately
/// unhandled here (`_markerFor`'s `default` case) — unlike `header`,
/// there's no native CommonMark syntax for paragraph alignment or
/// direction, and inventing a raw-HTML escape-hatch convention is more
/// risk than a not-yet-visually-rendered property (see
/// `ParagraphAlignment`'s/`ParagraphTextDirection`'s doc comments)
/// currently justifies. Both survive document JSON save/load and HTML
/// export/import; a Markdown round-trip is a deliberate gap, not an
/// oversight.
class MarkdownExporter {
  const MarkdownExporter();

  String export(String text, List<TextAttribute> attributes) {
    if (text.isEmpty) return '';
    if (attributes.isEmpty) return text;

    final sorted = List<TextAttribute>.from(attributes)
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

      if (!isFirstParagraph) buffer.write('\n');
      buffer.write(_renderInline(text, pos, paragraphEnd, sorted));

      isFirstParagraph = false;
      if (nextNewline == -1) break;
      pos = nextNewline + 1;
    }

    return buffer.toString();
  }

  /// Renders `[start, end)` — one paragraph's worth of inline content —
  /// applying whatever `sorted` attributes overlap that range. An
  /// attribute already active when the window starts is opened before
  /// the loop (it may have started in an earlier paragraph); one still
  /// active when the window ends is force-closed there regardless of
  /// its true `.end` (it may continue into a later paragraph, which
  /// reopens it in its own call to this method). See `HtmlExporter
  /// ._renderInline`'s doc comment — same logic, hand-traced there
  /// against a spanning-attribute example before being reused here.
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
          return value == 'h1' ? '# ' : '## ';
        }
        return ''; // headers don't have closing markers in this model (line-based)
      default:
        return '';
    }
  }
}