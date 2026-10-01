import '../models/attribute_type.dart';
import '../models/code_block.dart';
import '../models/image_block.dart';
import '../models/text_attribute.dart';
import '../utils/url_detector.dart';

/// Parses a scoped subset of Markdown (and WhatsApp flavor) into plain
/// text plus [TextAttribute]s — not a CommonMark-compliant parser.
///
/// Supported: `**bold**`, `*italic*`/`_italic_`, `~~strikethrough~~`,
/// `` `code` ``, `[text](url)` links, `# `/`## ` headers, and WhatsApp's
/// `*bold*`, `_italic_`, `~strikethrough~`, ` ```monospace``` `.
///
/// List markers (`- `, `* `, `+ `, `1. `, including `- [ ] `/`- [x] `
/// checkboxes) are left alone as literal text rather than stripped,
/// preserving the source note's visual list shape.
class MarkdownImporter {
  const MarkdownImporter();

  // An opening code fence on a line of its own: three or more backticks or
  // tildes, optionally followed by an info string whose first word is the
  // language. A line like "```text```" (WhatsApp monospace) does not match.
  static final RegExp _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*([^`\s]*)[^`]*$');

  /// Parses `markdown`, returning plain text and attributes relative to it.
  ///
  /// Block structure: fenced code becomes a block-level code block (its text
  /// kept exactly, no inline parsing), headings become headers, a run of blank
  /// lines becomes one blank line, and leading/trailing blank lines are
  /// dropped. Everything else is a line per paragraph, with list markers and
  /// `> ` quote markers kept as literal text.
  ({String text, List<TextAttribute> attributes, List<ImportedImage> images}) parse(String markdown, {bool images = false}) {
    final imported = <ImportedImage>[];
    final source = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = source.split('\n');

    // First pass: find fenced blocks, so they can neither confuse flavor
    // detection nor be inline-parsed.
    final blocks = <({int open, int close, String? lang})>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _fenceOpen.firstMatch(lines[i]);
      if (m == null) continue;
      final fence = m.group(1)!;
      var close = -1;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trimRight().trimLeft();
        if (t.length >= fence.length && t[0] == fence[0] && t.split('').every((c) => c == fence[0])) {
          close = j;
          break;
        }
      }
      blocks.add((open: i, close: close == -1 ? lines.length : close, lang: normalizeCodeLanguage(m.group(2))));
      i = close == -1 ? lines.length : close;
    }
    final inBlock = <int, int>{}; // line -> index into blocks
    for (var k = 0; k < blocks.length; k++) {
      for (var i = blocks[k].open; i <= blocks[k].close && i < lines.length; i++) {
        inBlock[i] = k;
      }
    }

    final prose = [for (var i = 0; i < lines.length; i++) if (!inBlock.containsKey(i)) lines[i]].join('\n');
    final isWhatsApp = _detectWhatsAppFlavor(prose);

    final buffer = StringBuffer();
    final attributes = <TextAttribute>[];
    var wroteAny = false;
    var pendingBlank = false;

    void startLine() {
      if (wroteAny) buffer.write('\n');
      if (pendingBlank && wroteAny) buffer.write('\n');
      pendingBlank = false;
      wroteAny = true;
    }

    var i = 0;
    while (i < lines.length) {
      final blockIndex = inBlock[i];
      if (blockIndex != null) {
        final block = blocks[blockIndex];
        final bodyStart = block.open + 1;
        final bodyEnd = block.close; // exclusive
        final body = bodyStart < bodyEnd ? lines.sublist(bodyStart, bodyEnd) : <String>[];
        if (body.isEmpty) {
          // An empty fence still yields one (empty) code line.
          startLine();
          // No text to carry a span: an empty code block is dropped.
        } else {
          startLine();
          final start = buffer.length;
          buffer.write(body.join('\n'));
          attributes.add(TextAttribute(
            start: start,
            end: buffer.length,
            type: AttributeType.header,
            value: codeBlockLevelFor(block.lang),
          ));
        }
        i = block.close + 1;
        continue;
      }

      final line = lines[i];
      if (line.trim().isEmpty) {
        if (wroteAny) pendingBlank = true;
        i++;
        continue;
      }

      // A line that is only a picture, `![alt](address)`: a block of blank rows
      // for the picture to be filled into once it is fetched.
      final pic = images && imported.length < maxImportedImages ? _pictureLine.firstMatch(line.trim()) : null;
      if (pic != null && isImportableImageSource(pic.group(2)!)) {
        final rows = 6;
        final level = imageLevelFor(pendingImageId, newImageInstance());
        startLine();
        final start = buffer.length;
        buffer.write('\n' * (rows - 1));
        attributes.add(TextAttribute(start: start, end: buffer.length, type: AttributeType.header, value: level));
        imported.add(ImportedImage(level: level, source: pic.group(2)!, alt: pic.group(1)!.trim()));
        i++;
        continue;
      }

      final stripped = _stripPrefix(line);
      final inline = _parseInline(stripped.rest, isWhatsApp);
      startLine();
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
      i++;
    }

    return (text: buffer.toString(), attributes: attributes, images: imported);
  }

  static final RegExp _pictureLine = RegExp(r'^!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)$');

  bool _detectWhatsAppFlavor(String markdown) {
    final hasWAExclusive = markdown.contains('```') ||
        RegExp(r'(^|\s)~[^~]+~($|\s)').hasMatch(markdown);
    final hasMDExclusive = markdown.contains('**') || markdown.contains('~~');

    // WhatsApp only if it has a WA-exclusive marker and no MD-exclusive
    // one; ambiguous or mixed markers default to Markdown.
    return hasWAExclusive && !hasMDExclusive;
  }

  ({String? headerLevel, String rest}) _stripPrefix(String line) {
    if (line.startsWith('### ')) return (headerLevel: 'h3', rest: line.substring(4));
    if (line.startsWith('## ')) return (headerLevel: 'h2', rest: line.substring(3));
    if (line.startsWith('# ')) return (headerLevel: 'h1', rest: line.substring(2));
    final headerMatch = RegExp(r'^(#{4,6}) ').firstMatch(line);
    if (headerMatch != null) return (headerLevel: 'h3', rest: line.substring(headerMatch.end));

    return (headerLevel: null, rest: line);
  }

  ({String text, List<TextAttribute> attributes}) _parseInline(String line, bool isWhatsApp) {
    // Backslash escapes: `\*` is a literal `*`. The backslash is dropped from
    // the output and the escaped character never starts a link or emphasis.
    final escaped = <int>{};
    final dropped = <int>{};
    for (var k = 0; k + 1 < line.length; k++) {
      if (line[k] == r'\' && _escapable.contains(line[k + 1])) {
        dropped.add(k);
        escaped.add(k + 1);
        k++;
      }
    }

    // Links first
    final links = <({int start, int end, int textStart, int textEnd, String url})>[];
    var i = 0;
    while (i < line.length) {
      if (line[i] == '<' && !escaped.contains(i)) {
        // Autolink: <https://example.com> or <name@example.com>
        final close = line.indexOf('>', i + 1);
        if (close != -1) {
          final inner = line.substring(i + 1, close);
          String? url;
          if (RegExp(r'^(https?|mailto|tel):[^\s<>]+$', caseSensitive: false).hasMatch(inner)) {
            url = inner;
          } else if (RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(inner)) {
            url = 'mailto:$inner';
          }
          if (url != null) {
            links.add((start: i, end: close + 1, textStart: i + 1, textEnd: close, url: url));
            i = close + 1;
            continue;
          }
        }
      }
      if (line[i] == '[' && !escaped.contains(i)) {
        // `![alt](src)` inside a line of text: the picture itself is not shown
        // there, so it reads as a link named by its alt text (no stray `!`).
        if (i > 0 && line[i - 1] == '!' && !escaped.contains(i - 1)) dropped.add(i - 1);
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
    final occurrences = <({int index, String marker, bool canOpen, bool canClose})>[];
    i = 0;
    while (i < line.length) {
      if (insideLink(i) || escaped.contains(i) || dropped.contains(i)) {
        i++;
        continue;
      }
      final marker = _markerAt(line, i, isWhatsApp);
      if (marker != null) {
        // Flanking, as in CommonMark: an opener is followed by text and a closer
        // preceded by it, so `2 * 3 * 4` is arithmetic, not emphasis. `_` also
        // may not open or close inside a word (snake_case_name).
        final before = i > 0 ? line[i - 1] : null;
        final after = i + marker.length < line.length ? line[i + marker.length] : null;
        var canOpen = after != null && !_isSpace(after);
        var canClose = before != null && !_isSpace(before);
        if (marker.startsWith('_')) {
          if (before != null && _isWordChar(before)) canOpen = false;
          if (after != null && _isWordChar(after)) canClose = false;
        }
        if (marker.startsWith('`') && !isWhatsApp) {
          canOpen = after != null;
          canClose = before != null;
        }
        occurrences.add((index: i, marker: marker, canOpen: canOpen, canClose: canClose));
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

      if (!dropped.contains(i)) buffer.write(line[i]);
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

  static const _escapable = r'\`*_{}[]()#+-.!~<>|';

  static bool _isSpace(String ch) => ch.trim().isEmpty;
  static bool _isWordChar(String ch) => RegExp(r'[A-Za-z0-9]').hasMatch(ch);

  List<({int openIndex, int closeIndex, int markerLength, AttributeType type})> _pairMarkers(
      List<({int index, String marker, bool canOpen, bool canClose})> occurrences,
      bool isWhatsApp,
      ) {
    final pairs = <({int openIndex, int closeIndex, int markerLength, AttributeType type})>[];
    final openStacks = <String, List<int>>{};

    for (final occ in occurrences) {
      final stack = openStacks.putIfAbsent(occ.marker, () => []);
      if (stack.isNotEmpty && occ.canClose) {
        final openIndex = stack.removeLast();
        if (occ.index > openIndex + occ.marker.length) {
          pairs.add((
          openIndex: openIndex,
          closeIndex: occ.index,
          markerLength: occ.marker.length,
          type: _markerType(occ.marker, isWhatsApp),
          ));
        }
      } else if (occ.canOpen) {
        stack.add(occ.index);
      }
    }
    return pairs;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}