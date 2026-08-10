import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/url_detector.dart';

/// Parses a deliberately scoped *subset* of Markdown (and WhatsApp flavor)
/// into plain text plus [TextAttribute]s — not a CommonMark-compliant parser.
///
/// Supported: `**bold**`, `*italic*` / `_italic_`, `~~strikethrough~~`,
/// `` `code` ``, `[text](url)` links, and `# ` / `## ` headers at the
/// start of a line.
///
/// WhatsApp flavor: `*bold*`, `_italic_`, `~strikethrough~`, ` ```monospace``` `.
///
/// List markers (`- `, `* `, `+ `, `1. `) are intentionally left alone —
/// list formatting was removed from [AttributeType] (see its doc comment
/// for why), so a line starting with one of these is imported as literal
/// text, prefix included, rather than silently stripping the prefix and
/// losing the visual list shape the source note had.
class MarkdownImporter {
  const MarkdownImporter();

  /// Parses `markdown`, returning plain text and attributes relative to
  /// it — ready to hand to `CommandDispatcher.pasteRich`/
  /// `RichEditorController.pasteMarkdown`.
  ({String text, List<TextAttribute> attributes}) parse(String markdown) {
    final isWhatsApp = _detectWhatsAppFlavor(markdown);
    final lines = markdown.split('\n');
    final buffer = StringBuffer();
    final attributes = <TextAttribute>[];

    for (var i = 0; i < lines.length; i++) {
      final stripped = _stripPrefix(lines[i]);
      final inline = _parseInline(stripped.rest, isWhatsApp);

      final lineStart = buffer.length;
      buffer.write(inline.text);
      final lineEnd = buffer.length;

      for (final attr in inline.attributes) {
        attributes.add(attr.copyWith(start: attr.start + lineStart, end: attr.end + lineStart));
      }
      if (stripped.headerLevel != null && lineEnd > lineStart) {
        attributes.add(TextAttribute(
          start: lineStart,
          end: lineEnd,
          type: AttributeType.header,
          value: stripped.headerLevel,
        ));
      }

      if (i < lines.length - 1) buffer.write('\n');
    }

    return (text: buffer.toString(), attributes: attributes);
  }

  bool _detectWhatsAppFlavor(String markdown) {
    final hasWAExclusive = markdown.contains('```') ||
        RegExp(r'(^|\s)~[^~]+~($|\s)').hasMatch(markdown);
    final hasMDExclusive = markdown.contains('**') || markdown.contains('~~');

    // If it has WA markers and NO MD markers, it's highly likely WhatsApp.
    // If it has both, we default to Markdown to be safe.
    // If it has only ambiguous markers like `*text*`, we fallback to Markdown.
    return hasWAExclusive && !hasMDExclusive;
  }

  ({String? headerLevel, String rest}) _stripPrefix(String line) {
    if (line.startsWith('## ')) return (headerLevel: 'h2', rest: line.substring(3));
    if (line.startsWith('# ')) return (headerLevel: 'h1', rest: line.substring(2));
    final headerMatch = RegExp(r'^(#{3,6}) ').firstMatch(line);
    if (headerMatch != null) return (headerLevel: 'h2', rest: line.substring(headerMatch.end));

    // List-prefixed lines ('- ', '* ', '+ ', '1. ') are intentionally
    // left untouched here and fall through to the plain-text case below
    // — see the class doc comment.
    return (headerLevel: null, rest: line);
  }

  ({String text, List<TextAttribute> attributes}) _parseInline(String line, bool isWhatsApp) {
    // Links first
    final links = <({int start, int end, int textStart, int textEnd, String url})>[];
    var i = 0;
    while (i < line.length) {
      if (line[i] == '[') {
        final closeBracket = line.indexOf(']', i + 1);
        if (closeBracket != -1 && closeBracket + 1 < line.length && line[closeBracket + 1] == '(') {
          final closeParen = line.indexOf(')', closeBracket + 2);
          if (closeParen != -1) {
            final linkText = line.substring(i + 1, closeBracket);
            final url = line.substring(closeBracket + 2, closeParen);
            if (linkText.isNotEmpty && url.isNotEmpty) {
              links.add((start: i, end: closeParen + 1, textStart: i + 1, textEnd: closeBracket, url: url));
              i = closeParen + 1;
              continue;
            }
          }
        }
      }
      i++;
    }
    bool insideLink(int index) => links.any((l) => index >= l.start && index < l.end);

    // Emphasis markers outside link ranges
    final occurrences = <({int index, String marker})>[];
    i = 0;
    while (i < line.length) {
      if (insideLink(i)) {
        i++;
        continue;
      }
      final marker = _markerAt(line, i, isWhatsApp);
      if (marker != null) {
        occurrences.add((index: i, marker: marker));
        i += marker.length;
      } else {
        i++;
      }
    }
    final pairs = _pairMarkers(occurrences, isWhatsApp);

    // Final pass: write output and collect attributes
    final buffer = StringBuffer();
    final attributes = <TextAttribute>[];
    final pairOutputStart = <int, int>{};

    i = 0;
    while (i < line.length) {
      final link = links.where((l) => l.start == i).firstOrNull;
      if (link != null) {
        final start = buffer.length;
        buffer.write(line.substring(link.textStart, link.textEnd));
        attributes.add(TextAttribute(start: start, end: buffer.length, type: AttributeType.link, value: link.url));
        i = link.end;
        continue;
      }

      final openPairIndex = pairs.indexWhere((p) => p.openIndex == i);
      if (openPairIndex != -1) {
        pairOutputStart[openPairIndex] = buffer.length;
        i += pairs[openPairIndex].markerLength;
        continue;
      }
      final closePairIndex = pairs.indexWhere((p) => p.closeIndex == i);
      if (closePairIndex != -1) {
        final pair = pairs[closePairIndex];
        attributes.add(TextAttribute(
          start: pairOutputStart[closePairIndex]!,
          end: buffer.length,
          type: pair.type,
        ));
        i += pair.markerLength;
        continue;
      }

      buffer.write(line[i]);
      i++;
    }

    // Autolink bare URLs in the resulting plain text, avoiding existing links
    final plainText = buffer.toString();
    final urls = detectAllUrls(plainText);
    for (final u in urls) {
      final overlaps = attributes.any((a) => a.type == AttributeType.link && a.intersects(u.start, u.end));
      if (!overlaps) {
        attributes.add(TextAttribute(start: u.start, end: u.end, type: AttributeType.link, value: u.href));
      }
    }

    return (text: plainText, attributes: attributes);
  }

  String? _markerAt(String line, int i, bool isWhatsApp) {
    if (isWhatsApp) {
      if (_startsWith(line, i, '```')) return '```';
      if (line[i] == '*') return '*';
      if (line[i] == '_') return '_';
      if (line[i] == '~') return '~';
      return null;
    }
    if (_startsWith(line, i, '**')) return '**';
    if (_startsWith(line, i, '__')) return '__';
    if (_startsWith(line, i, '~~')) return '~~';
    if (line[i] == '`') return '`';
    if (line[i] == '*') return '*';
    if (line[i] == '_') return '_';
    return null;
  }

  bool _startsWith(String line, int i, String pattern) {
    if (i + pattern.length > line.length) return false;
    return line.substring(i, i + pattern.length) == pattern;
  }

  AttributeType _markerType(String marker, bool isWhatsApp) {
    if (isWhatsApp) {
      switch (marker) {
        case '*': return AttributeType.bold;
        case '_': return AttributeType.italic;
        case '~': return AttributeType.strikethrough;
        case '```': return AttributeType.code;
      }
    }
    switch (marker) {
      case '**':
      case '__':
        return AttributeType.bold;
      case '~~':
        return AttributeType.strikethrough;
      case '`':
        return AttributeType.code;
      default: // '*' or '_'
        return AttributeType.italic;
    }
  }

  List<({int openIndex, int closeIndex, int markerLength, AttributeType type})> _pairMarkers(
      List<({int index, String marker})> occurrences,
      bool isWhatsApp,
      ) {
    final pairs = <({int openIndex, int closeIndex, int markerLength, AttributeType type})>[];
    final openStacks = <String, List<int>>{};

    for (final occ in occurrences) {
      final stack = openStacks.putIfAbsent(occ.marker, () => []);
      if (stack.isNotEmpty) {
        final openIndex = stack.removeLast();
        if (occ.index > openIndex + occ.marker.length) {
          pairs.add((
          openIndex: openIndex,
          closeIndex: occ.index,
          markerLength: occ.marker.length,
          type: _markerType(occ.marker, isWhatsApp),
          ));
        }
      } else {
        stack.add(occ.index);
      }
    }
    return pairs;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}