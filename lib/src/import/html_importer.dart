import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';
import '../utils/url_detector.dart';

// One formatting frame currently "open" while walking the DOM — e.g.
// inside a `<b>` tag, every text node encountered gets a bold
// [TextAttribute] for its own range.
class _StyleFrame {
  final AttributeType type;
  final Object? value;
  const _StyleFrame(this.type, this.value);
}

// Tracks the nearest enclosing <ul>/<ol> while walking, so a <li> knows
// what marker to emit, its number (for an ordered list), and its
// nesting depth. A fresh instance is created per <ul>/<ol> visited,
// including nested ones, so numbering restarts correctly for each list.
class _ListContext {
  final bool ordered;
  final int depth;
  int _counter = 0;
  _ListContext(this.ordered, this.depth);
  int next() => ++_counter;

  String get indent => '  ' * depth;
}

/// Parses HTML into plain text plus [TextAttribute]s, for pasting content
/// copied from a browser or another rich-text source.
///
/// Recognized tags: `<b>`/`<strong>`, `<i>`/`<em>`, `<u>`,
/// `<s>`/`<strike>`/`<del>`, `<code>`, `<a href="...">`, and `<h1>`–`<h6>`
/// (h3 and deeper collapse to h2). `<br>` becomes a newline; other
/// block-level elements are newline-separated but otherwise treated as
/// plain text, so table/blockquote structure is discarded, only their
/// text content survives. `<script>`/`<style>` contents are skipped.
///
/// List items are the exception: a `<li>` inside a `<ul>`/`<ol>` gets a
/// literal `'  - '`/`'  N. '` prefix written into the output text
/// (real characters, not a stored attribute), with 2 more spaces per
/// nesting level.
class HtmlImporter {
  const HtmlImporter();

  static const _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'blockquote', 'ul', 'ol', 'tr', 'table',
  };

  ({String text, List<TextAttribute> attributes}) parse(String htmlString) {
    final document = html_parser.parse(htmlString);
    final body = document.body;
    final buffer = StringBuffer();
    final attributes = <TextAttribute>[];

    if (body != null) {
      _walk(body, buffer, attributes, const [], null);
    }

    var text = buffer.toString();
    // Block elements leave a trailing newline from closing the last block.
    while (text.endsWith('\n')) {
      text = text.substring(0, text.length - 1);
    }

    return (text: text, attributes: _mergeAttributes(attributes));
  }

  void _walk(
      dom.Node node,
      StringBuffer buffer,
      List<TextAttribute> attributes,
      List<_StyleFrame> stack,
      _ListContext? currentList, {
        int? suppressBreakAt,
      }) {
    if (node is dom.Text) {
      var content = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (content.isEmpty) return;

      // Skip insignificant inter-tag whitespace (pretty-printed source
      // HTML between sibling elements) at a boundary where it isn't
      // needed, matching how browsers collapse it. Without this,
      // newlines between e.g. <li> tags paste in as blank lines.
      if (content == ' ' &&
          (buffer.isEmpty ||
              buffer.toString().endsWith(' ') ||
              buffer.toString().endsWith('\n'))) {
        return;
      }

      final start = buffer.length;
      buffer.write(content);
      for (final frame in stack) {
        attributes.add(TextAttribute(start: start, end: buffer.length, type: frame.type, value: frame.value));
      }

      final alreadyInLink = stack.any((f) => f.type == AttributeType.link);
      if (!alreadyInLink) {
        final urls = detectAllUrls(content);
        for (final u in urls) {
          attributes.add(TextAttribute(
            start: start + u.start,
            end: start + u.end,
            type: AttributeType.link,
            value: u.href,
          ));
        }
      }
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName;
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }
    if (tag == 'script' || tag == 'style') return;

    final isBlock = _blockTags.contains(tag);
    if (isBlock &&
        buffer.isNotEmpty &&
        !buffer.toString().endsWith('\n') &&
        buffer.length != suppressBreakAt) {
      buffer.write('\n');
    }

    // A <ul>/<ol> starts a fresh list scope for its own direct <li>
    // children; nested lists get their own counter and one deeper indent.
    var childListContext = currentList;
    // suppressBreakAt lets one block wrapper right after a list marker
    // (e.g. Google Docs' `<li><p>text</p></li>`) skip the leading-break
    // check below, keeping the marker glued to its own item's text.
    var childSuppressBreakAt = suppressBreakAt;
    if (tag == 'ul') {
      childListContext = _ListContext(false, (currentList?.depth ?? 0) + 1);
    } else if (tag == 'ol') {
      childListContext = _ListContext(true, (currentList?.depth ?? 0) + 1);
    } else if (tag == 'li' && currentList != null) {
      // Defensive: don't stack a generated prefix on top of a literal
      // one already present in the <li>'s own text.
      final liOwnText = node.text.trimLeft();
      final alreadyHasPrefix = listPrefixLength(liOwnText, 0) > 0;
      if (!alreadyHasPrefix) {
        final indent = currentList.indent;
        buffer.write(currentList.ordered ? '$indent${currentList.next()}. ' : '$indent- ');
        childSuppressBreakAt = buffer.length;
      } else if (currentList.ordered) {
        currentList.next();
      }
    }

    final List<_StyleFrame> extraFrames = _framesFromStyles(node);
    final frame = _frameFor(tag, node);

    var currentStack = stack;
    if (frame != null) currentStack = [...currentStack, frame];
    currentStack = [...currentStack, ...extraFrames];

    final dir = node.attributes['dir'];
    if (dir == 'rtl' || dir == 'ltr') {
      currentStack = [...currentStack, _StyleFrame(AttributeType.textDirection, dir)];
    }

    if (tag == 'a') {
      final href = node.attributes['href'];
      if (href != null && href.isNotEmpty) {
        currentStack = [...currentStack, _StyleFrame(AttributeType.link, href)];
      }
    }

    for (final child in node.nodes) {
      _walk(child, buffer, attributes, currentStack, childListContext,
          suppressBreakAt: childSuppressBreakAt);
    }

    if (isBlock && buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
      buffer.write('\n');
    }
  }

  List<_StyleFrame> _framesFromStyles(dom.Element element) {
    final style = element.attributes['style'];
    if (style == null || style.isEmpty) return const [];

    final frames = <_StyleFrame>[];
    final declarations = style.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty);
    for (final decl in declarations) {
      final parts = decl.split(':').map((s) => s.trim()).toList();
      if (parts.length < 2) continue;
      final property = parts[0].toLowerCase();
      final value = parts[1].toLowerCase();

      if (property == 'font-weight' && (value == 'bold' || value == '700' || value == '800' || value == '900')) {
        frames.add(const _StyleFrame(AttributeType.bold, null));
      } else if (property == 'font-style' && value == 'italic') {
        frames.add(const _StyleFrame(AttributeType.italic, null));
      } else if (property == 'text-decoration') {
        if (value.contains('underline')) {
          frames.add(const _StyleFrame(AttributeType.underline, null));
        }
        if (value.contains('line-through')) {
          frames.add(const _StyleFrame(AttributeType.strikethrough, null));
        }
      } else if (property == 'text-align' &&
          (value == 'left' || value == 'center' || value == 'right')) {
        // value must match ParagraphAlignment.name; 'justify' has no
        // counterpart and is left unrecognized.
        frames.add(_StyleFrame(AttributeType.align, value));
      }
    }
    return frames;
  }

  List<TextAttribute> _mergeAttributes(List<TextAttribute> raw) {
    if (raw.isEmpty) return raw;

    // Group by type and value, then sort by start.
    final grouped = <String, List<TextAttribute>>{};
    for (final attr in raw) {
      final key = '${attr.type.name}_${attr.value}';
      grouped.putIfAbsent(key, () => []).add(attr);
    }

    final merged = <TextAttribute>[];
    for (final list in grouped.values) {
      list.sort((a, b) => a.start.compareTo(b.start));

      var current = list[0];
      for (var i = 1; i < list.length; i++) {
        final next = list[i];
        if (next.start <= current.end) {
          // Overlapping or contiguous
          current = current.copyWith(end: next.end > current.end ? next.end : current.end);
        } else {
          merged.add(current);
          current = next;
        }
      }
      merged.add(current);
    }

    return merged;
  }

  _StyleFrame? _frameFor(String? tag, dom.Element node) {
    switch (tag) {
      case 'b':
      case 'strong':
        return const _StyleFrame(AttributeType.bold, null);
      case 'i':
      case 'em':
        return const _StyleFrame(AttributeType.italic, null);
      case 'u':
        return const _StyleFrame(AttributeType.underline, null);
      case 's':
      case 'strike':
      case 'del':
        return const _StyleFrame(AttributeType.strikethrough, null);
      case 'code':
        return const _StyleFrame(AttributeType.code, null);
      case 'h1':
        return const _StyleFrame(AttributeType.header, 'h1');
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return const _StyleFrame(AttributeType.header, 'h2');
      default:
        return null;
    }
  }
}