import '../models/attribute_type.dart';
import '../models/text_attribute.dart';

/// Parses a deliberately scoped *subset* of Markdown into plain text plus
/// [TextAttribute]s — not a CommonMark-compliant parser.
///
/// Supported: `**bold**`, `*italic*` / `_italic_`, `~~strikethrough~~`,
/// `` `code` ``, `[text](url)` links, and `# ` / `## ` headers at the
/// start of a line (mapped to h1/h2 — this editor doesn't model h3+, so
/// `###` and deeper collapse to h2).
///
/// Explicitly NOT supported, by design — these would pull this "lightweight
/// inline formatting" editor toward being a document/block editor, which
/// the product brief rules out: lists, blockquotes, tables, images,
/// reference-style links, `***triple***` markers, backslash escaping, and
/// nested/combined emphasis within a single run (e.g.
/// `**bold *and italic* together**` — the inner `*...*` won't parse
/// correctly layered inside the outer `**...**`).
///
/// Unclosed markers degrade gracefully: `**bold` with no closing `**`
/// renders as the literal text `**bold`, not silently-dropped characters
/// or a crash — see [_pairMarkers].
class MarkdownImporter {
  const MarkdownImporter();

  /// Parses `markdown`, returning plain text and attributes relative to
  /// it — ready to hand to `CommandDispatcher.pasteRich`/
  /// `RichEditorController.pasteMarkdown`.
  ({String text, List<TextAttribute> attributes}) parse(String markdown) {
    final lines = markdown.split('\n');
    final buffer = StringBuffer();
    final attributes = <TextAttribute>[];

    for (var i = 0; i < lines.length; i++) {
      final stripped = _stripHeaderPrefix(lines[i]);
      final inline = _parseInline(stripped.rest);

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

  ({String? headerLevel, String rest}) _stripHeaderPrefix(String line) {
    if (line.startsWith('## ')) return (headerLevel: 'h2', rest: line.substring(3));
    if (line.startsWith('# ')) return (headerLevel: 'h1', rest: line.substring(2));
    // Collapse any deeper heading level to h2 — this editor only models
    // two header levels.
    final match = RegExp(r'^(#{3,6}) ').firstMatch(line);
    if (match != null) return (headerLevel: 'h2', rest: line.substring(match.end));
    return (headerLevel: null, rest: line);
  }

  ({String text, List<TextAttribute> attributes}) _parseInline(String line) {
    // Links first — they're atomic (`[text](url)` always resolves in one
    // step) and link text is treated as plain (no nested emphasis parsed
    // inside brackets, a deliberate scope limit).
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

    // Emphasis markers outside link ranges, paired left-to-right per
    // marker string.
    final occurrences = <({int index, String marker})>[];
    i = 0;
    while (i < line.length) {
      if (insideLink(i)) {
        i++;
        continue;
      }
      final marker = _markerAt(line, i);
      if (marker != null) {
        occurrences.add((index: i, marker: marker));
        i += marker.length;
      } else {
        i++;
      }
    }
    final pairs = _pairMarkers(occurrences);

    // Final pass: write output, substituting links, consuming matched
    // marker delimiters, and recording attributes in output coordinates.
    // Anything not part of a link or a matched pair — including any
    // marker character that never found its match — is written literally.
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

    return (text: buffer.toString(), attributes: attributes);
  }

  String? _markerAt(String line, int i) {
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

  AttributeType _markerType(String marker) {
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

  /// Pairs marker occurrences into (open, close) spans using one stack
  /// per marker string, left to right — the first unmatched occurrence
  /// of a marker opens it, the next occurrence of the *same* marker
  /// string closes it. A marker occurrence that never gets closed (odd
  /// count of that marker on the line) is simply never added to the
  /// result, which is what makes unclosed markers degrade to literal
  /// text in [_parseInline] rather than eating the character silently.
  List<({int openIndex, int closeIndex, int markerLength, AttributeType type})> _pairMarkers(
      List<({int index, String marker})> occurrences,
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
          type: _markerType(occ.marker),
          ));
        }
        // Empty content between markers (e.g. "****") — drop the pair
        // silently rather than creating a zero-width attribute; those
        // characters simply won't match any pair in the final pass and
        // fall through as literal text.
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