import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';

/// Converts plain text and [TextAttribute]s into an HTML string for
/// copying to the system clipboard or exporting to other apps.
///
/// List paragraphs get real `<ul>/<ol>/<li>` structure, detected purely
/// from literal text via [listPrefixLength]/[listTypeOfPrefix] — the
/// same derived-from-text approach used everywhere else list-ness is
/// checked in this codebase, not a stored `ParagraphIndex` field. This
/// exporter has to work on arbitrary substrings (e.g.
/// `ClipboardManager.copy()` passes a clipped selection, not the whole
/// document), which a `ParagraphIndex`-based approach couldn't do
/// anyway — `ParagraphIndex` offsets are relative to the whole
/// document, not to whatever range got copied.
class HtmlExporter {
  const HtmlExporter();

  String export(String text, List<TextAttribute> attributes) {
    if (text.isEmpty) return '';

    final sorted = List<TextAttribute>.from(attributes)
      ..sort((a, b) {
        if (a.start != b.start) return a.start.compareTo(b.start);
        return b.end.compareTo(a.end);
      });

    final buffer = StringBuffer();
    ParagraphListType? openListType;
    var pos = 0;
    var isFirstParagraph = true;

    void closeOpenList() {
      if (openListType != null) {
        buffer.write(openListType == ParagraphListType.bullet ? '</ul>' : '</ol>');
        openListType = null;
      }
    }

    while (true) {
      final nextNewline = text.indexOf('\n', pos);
      final paragraphEnd = nextNewline == -1 ? text.length : nextNewline;

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
      } else {
        closeOpenList();
        // '<br>' between paragraphs, matching the original character-
        // by-character sweep's '\n' -> '<br>' behavior — just emitted
        // per-paragraph now instead of per-character. Never before the
        // very first paragraph.
        if (!isFirstParagraph) buffer.write('<br>');
        buffer.write(_renderInline(text, contentStart, paragraphEnd, sorted));
      }

      isFirstParagraph = false;
      if (nextNewline == -1) break;
      pos = nextNewline + 1;
    }
    closeOpenList();

    return buffer.toString();
  }

  /// Renders the inline (character-level) content of `[start, end)`,
  /// applying whatever `sorted` attributes overlap that range —
  /// extracted from the original single-pass sweep so it can be called
  /// once per paragraph instead of once for the whole document.
  ///
  /// Handles three cases a plain per-character sweep over the *whole*
  /// text didn't need to: an attribute already active when this window
  /// starts (opened before the loop, since the sweep only opens tags
  /// exactly at their own `.start`, which may be earlier), an attribute
  /// still active when the window ends (force-closed at `end`
  /// regardless of its true `.end`), and escaping. The force-close
  /// matters specifically for list content: `<li>` elements are
  /// siblings, not nested, so a `<b>` span that used to run across two
  /// list items in the flat document has to become two separate
  /// `<b>...</b>` regions in the exported HTML — `<b>` spanning across
  /// `</li><li>` isn't valid structure.
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
        buffer.write(_tagFor(attr.type, isOpen: false));
      }
      final opening = sorted.where((a) => a.start == i && a.start >= start);
      for (final attr in opening) {
        buffer.write(_tagFor(attr.type, value: attr.value, isOpen: true));
      }

      final char = text[i];
      if (char == '<') {
        buffer.write('&lt;');
      } else if (char == '>') {
        buffer.write('&gt;');
      } else if (char == '&') {
        buffer.write('&amp;');
      } else {
        buffer.write(char);
      }
    }

    final stillOpenAtEnd = sorted.where((a) => a.start < end && a.end >= end && a.start < a.end).toList()
      ..sort((a, b) => b.start.compareTo(a.start)); // innermost (latest-opened) first
    for (final attr in stillOpenAtEnd) {
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