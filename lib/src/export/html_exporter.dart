import '../models/attribute_type.dart';
import '../models/code_block.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';

/// Converts plain text and [TextAttribute]s into an HTML string for
/// copying to the system clipboard or exporting to other apps.
///
/// List paragraphs get real `<ul>/<ol>/<li>` structure, detected from
/// literal text via [listPrefixLength]/[listTypeOfPrefix] so this also
/// works on arbitrary substrings (e.g. a clipped selection), not just
/// the whole document.
class HtmlExporter {
  /// With [marker] set, the output starts with a generator `<meta>` that
  /// `HtmlImporter` recognises as this exporter's own grammar (one block or
  /// `<br>`-separated run per paragraph), so it re-imports line for line
  /// instead of with the paragraph spacing it adds to arbitrary web pages.
  const HtmlExporter({this.marker = false});

  final bool marker;

  /// The generator tag [marker] emits.
  static const generatorMeta = '<meta name="generator" content="lightweight_rich_editor">';

  String export(String text, List<TextAttribute> attributes) {
    if (text.isEmpty) return '';
    final out = _export(text, attributes);
    return marker && out.isNotEmpty ? '$generatorMeta$out' : out;
  }

  String _export(String text, List<TextAttribute> attributes) {

    // Code blocks are emitted as <pre><code>, not as inline-attribute spans.
    bool isCodeSpan(TextAttribute a) =>
        a.type == AttributeType.header && isCodeBlockLevel(a.value as String?);
    final codeSpans = attributes.where(isCodeSpan).toList()..sort((a, b) => a.start.compareTo(b.start));
    final sorted = attributes.where((a) => !isCodeSpan(a)).toList()
      ..sort((a, b) {
        if (a.start != b.start) return a.start.compareTo(b.start);
        return b.end.compareTo(a.end);
      });

    final buffer = StringBuffer();
    ParagraphListType? openListType;
    var pos = 0;
    var isFirstParagraph = true;
    var afterBlock = false;
    var prevBlockElement = false;
    var blockEnded = false;

    void closeOpenList() {
      if (openListType != null) {
        buffer.write(openListType == ParagraphListType.bullet ? '</ul>' : '</ol>');
        openListType = null;
      }
    }

    while (true) {
      final nextNewline = text.indexOf('\n', pos);
      final paragraphEnd = nextNewline == -1 ? text.length : nextNewline;

      final code = codeSpans.where((a) => a.start <= pos && a.end >= pos && a.end > a.start).firstOrNull;
      if (code != null) {
        final wasList = openListType != null;
        closeOpenList();
        if (!isFirstParagraph && !afterBlock && !wasList && !prevBlockElement) buffer.write('<br>');
        prevBlockElement = true;
        final lang = codeBlockLanguage(code.value as String?);
        final codeEnd = code.end > text.length ? text.length : code.end;
        buffer.write('<pre><code${lang == null ? '' : ' class="language-$lang"'}>');
        buffer.write(_escape(text.substring(pos, codeEnd)));
        buffer.write('</code></pre>');
        isFirstParagraph = false;
        afterBlock = true;
        if (codeEnd >= text.length) break;
        pos = codeEnd + 1;
        continue;
      }

      final prefixLen = listPrefixLength(text, pos);
      final listType = prefixLen > 0 ? listTypeOfPrefix(text.substring(pos, pos + prefixLen)) : null;
      final contentStart = pos + prefixLen;

      if (listType != null) {
        if (openListType != listType) {
          closeOpenList();
          buffer.write(listType == ParagraphListType.bullet ? '<ul>' : '<ol>');
          openListType = listType;
        }
        buffer.write('<li>');
        buffer.write(_renderInline(text, contentStart, paragraphEnd, sorted));
        buffer.write('</li>');
        blockEnded = true;
      } else {
        final wasList = openListType != null;
        closeOpenList();
        // A block element already ends its line; a <br> after it would add a
        // second break on re-import.
        if (!isFirstParagraph && !afterBlock && !wasList && !prevBlockElement) buffer.write('<br>');
        buffer.write(_renderInline(text, contentStart, paragraphEnd, sorted));
        blockEnded = sorted.any(
          (a) =>
              (a.type == AttributeType.header ||
                  a.type == AttributeType.align ||
                  a.type == AttributeType.textDirection) &&
              a.start <= pos &&
              a.end > pos,
        );
      }
      prevBlockElement = blockEnded;
      blockEnded = false;

      isFirstParagraph = false;
      afterBlock = false;
      if (nextNewline == -1) break;
      pos = nextNewline + 1;
    }
    closeOpenList();

    return buffer.toString();
  }

  // Renders the inline content of [start, end), force-closing any
  // still-open attribute at the window end: needed because <li>
  // elements are siblings, not nested, so a span can't cross them.
  String _renderInline(String text, int start, int end, List<TextAttribute> sorted) {
    if (start >= end) return '';
    final buffer = StringBuffer();

    final activeAtStart = sorted.where((a) => a.start < start && a.end > start);
    for (final attr in activeAtStart) {
      buffer.write(_tagFor(attr.type, value: attr.value, isOpen: true));
    }

    for (var i = start; i < end; i++) {
      final closing = sorted.where((a) => a.end == i && a.start < end && a.end > start).toList().reversed;
      for (final attr in closing) {
        buffer.write(_tagFor(attr.type, value: attr.value, isOpen: false));
      }
      final opening = sorted.where((a) => a.start == i && a.start >= start);
      for (final attr in opening) {
        buffer.write(_tagFor(attr.type, value: attr.value, isOpen: true));
      }

      buffer.write(_escape(text[i]));
    }

    final stillOpenAtEnd = sorted.where((a) => a.start < end && a.end >= end && a.start < a.end).toList()
      ..sort((a, b) => b.start.compareTo(a.start)); // innermost (latest-opened) first
    for (final attr in stillOpenAtEnd) {
      buffer.write(_tagFor(attr.type, value: attr.value, isOpen: false));
    }

    return buffer.toString();
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

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
        final tag = value == 'h1' ? 'h1' : (value == 'h2' ? 'h2' : 'h3');
        return isOpen ? '<$tag>' : '</$tag>';
      case AttributeType.align:
        // value is ParagraphAlignment.name ('left'/'center'/'right').
        return isOpen ? '<div style="text-align:$value">' : '</div>';
      case AttributeType.textDirection:
        // dir is a plain attribute (not CSS) since that's what
        // HtmlImporter looks for; value is 'ltr'/'rtl'.
        return isOpen ? '<div dir="$value">' : '</div>';
      default:
        return '';
    }
  }
}
extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
