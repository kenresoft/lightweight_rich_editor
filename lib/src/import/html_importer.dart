import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';
import '../utils/url_detector.dart';

/// One formatting frame currently "open" while walking the DOM — e.g.
/// inside a `<b>` tag, every text node encountered gets a bold
/// [TextAttribute] for its own range.
class _StyleFrame {
  final AttributeType type;
  final Object? value;
  const _StyleFrame(this.type, this.value);
}

/// Tracks the nearest enclosing `<ul>`/`<ol>` while walking, so a `<li>`
/// knows what kind of marker to emit, what number it's up to (for an
/// ordered list), and how deeply nested it is.
///
/// A fresh [_ListContext] is created every time a `<ul>`/`<ol>` element
/// is visited — including a *nested* one — so numbering is always
/// correctly scoped to its own list (a second, unrelated `<ol>` later in
/// the same paste restarts at 1; a nested `<ol>` inside a `<li>` starts
/// its own count rather than continuing the outer one). [depth] is
/// separate from that: it's the outer list's [depth] plus one, so a
/// top-level list is depth 1 (2-space indent) and each further level of
/// `<ul>`/`<ol>` nesting adds 2 more spaces — see [indent].
class _ListContext {
  final bool ordered;
  final int depth;
  int _counter = 0;
  _ListContext(this.ordered, this.depth);
  int next() => ++_counter;

  /// The literal leading whitespace for a marker at this depth — real
  /// characters written into the output text, matching how this
  /// library represents *all* list indentation (see the removal notes
  /// on `AttributeType`): there's no separate "nesting level" concept
  /// stored anywhere, just how many literal spaces happen to precede
  /// the marker. `EditingEngine`/the renderer/the toolbar all already
  /// group and detect list runs by comparing this literal indent
  /// string, regardless of how it got there — generating 2 spaces per
  /// depth here doesn't require anything downstream to know depth is a
  /// concept at all.
  String get indent => '  ' * depth;
}

/// Parses HTML into plain text plus [TextAttribute]s, for pasting content
/// copied from a browser or another rich-text source.
///
/// Recognized tags: `<b>`/`<strong>` (bold), `<i>`/`<em>` (italic), `<u>`
/// (underline), `<s>`/`<strike>`/`<del>` (strikethrough), `<code>`,
/// `<a href="...">` (link), `<h1>`–`<h6>` (header — h3 and deeper collapse
/// to h2, this editor only models two levels). `<br>` becomes a newline;
/// block-level elements (`<p>`, `<div>`, `<li>`, `<blockquote>`, headers)
/// are separated by newlines but otherwise treated as plain text — this
/// is a text+inline-formatting importer, not a layout engine, so table
/// structure and blockquote indentation are discarded; only their text
/// content survives. `<script>`/`<style>` contents are never imported.
///
/// List items are the one exception: a `<li>` inside a `<ul>`/`<ol>`
/// gets a literal `'  - '`/`'  N. '` prefix written directly into the
/// output text — real characters, not a stored attribute — matching how
/// this library represents lists everywhere else (see the removal notes
/// on `AttributeType`: list markers are always literal text, detected
/// and styled presentationally at render time, never virtual/injected).
/// Nesting depth is real too: each level of `<ul>`/`<ol>` nesting adds 2
/// more leading spaces (level 1 = `'  '`, level 2 = `'    '`, ...) —
/// see [_ListContext.indent]. Nothing downstream needs to know "depth"
/// is a concept: `EditingEngine`/the renderer/the toolbar already group
/// and detect list runs purely by comparing literal indent strings,
/// regardless of how many spaces or how they got there. A `<li>` with
/// no enclosing `<ul>`/`<ol>` (malformed fragment) is left as plain
/// block text, same as before.
///
/// Depends on `package:html` for actual HTML parsing (handling malformed
/// markup, entities, nesting) rather than hand-rolling that — unlike
/// [MarkdownImporter], robust HTML parsing isn't reasonably hand-rollable
/// for arbitrary real-world input.
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
    // Block elements tend to leave a trailing newline (from closing the
    // last block) — trim it.
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

      // A text node that collapses to nothing but a single space is
      // insignificant *inter-tag* whitespace (indentation/newlines in
      // pretty-printed source HTML between sibling elements) whenever it
      // sits at a boundary that doesn't need it: the very start of the
      // output, right after a block element's own trailing newline, or
      // right after another already-collapsed space. Real browsers
      // collapse this same whitespace away when laying out block-level
      // content — without doing the same here, a `<ul>`/`<ol>` (or any
      // pretty-printed block markup) with newlines between its `<li>`
      // tags in the source would paste each one of those newlines in as
      // a literal lone-space "blank" line between list items, and
      // likewise between paragraphs — a real, reported bug ("web content
      // pasted adds extra lines... even lists"). Only a boundary
      // triggers the skip; whitespace between genuine inline content
      // (`'Hello <b>world</b>'`) still needs its space and is untouched,
      // since the buffer there ends in real text, not a boundary.
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

      // Autolink URLs found in plain text nodes if not already inside an <a> tag
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
    // children (see _ListContext) — including one nested inside a <li>
    // of an outer list, which shadows the outer context for its own
    // subtree without disturbing the outer list's own counter, and gets
    // one level deeper indentation than whatever list (if any) it's
    // nested inside. A <li> with no enclosing list (currentList ==
    // null) just falls through to plain block text, unchanged from
    // before.
    var childListContext = currentList;
    // The buffer length to hand to this element's own children as their
    // `suppressBreakAt` — normally just whatever was passed to this call
    // (propagated unchanged through plain containers), except right
    // after writing a list-item marker below, which sets a fresh one.
    var childSuppressBreakAt = suppressBreakAt;
    if (tag == 'ul') {
      childListContext = _ListContext(false, (currentList?.depth ?? 0) + 1);
    } else if (tag == 'ol') {
      childListContext = _ListContext(true, (currentList?.depth ?? 0) + 1);
    } else if (tag == 'li' && currentList != null) {
      // Defensive: if this <li>'s own text content already starts with
      // something that looks like a literal list prefix (unusual, but
      // possible if the source HTML had literal '- ' typed inside
      // otherwise-real <li> markup), don't stack a second, generated
      // one on top of it. Still advances the counter for an ordered
      // list even when skipped, so a later sibling's number isn't
      // thrown off by this one's marker not being written.
      final liOwnText = node.text.trimLeft();
      final alreadyHasPrefix = listPrefixLength(liOwnText, 0) > 0;
      if (!alreadyHasPrefix) {
        final indent = currentList.indent;
        buffer.write(currentList.ordered ? '$indent${currentList.next()}. ' : '$indent- ');
        // The marker was just written specifically to have this list
        // item's own content glued directly after it — but that content
        // is very commonly wrapped in its own block tag by real-world
        // sources (Google Docs/Notion/Word HTML exports routinely emit
        // `<li><p>text</p></li>`), and that wrapper's own leading-break
        // check above would otherwise see "buffer doesn't end with \n"
        // (it ends with the marker's trailing space) and push the
        // content onto its own line — leaving the marker orphaned alone
        // on the line above it, a real, reported bug ("bullet on one
        // line, text under it on the next"). Recording the buffer length
        // right after the marker, and comparing against it above, lets
        // exactly one block wrapper (however deeply nested, as long as
        // nothing else has written to the buffer yet) skip that break; the
        // instant any real content is written, `buffer.length` moves past
        // this point and later siblings/blocks break normally again.
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

    // A plain HTML attribute, not a style declaration — `dir="rtl"`/
    // `dir="ltr"` on any element, matching what HtmlExporter emits for
    // AttributeType.textDirection. Any other value (or none) is ignored,
    // same "unrecognized value, not imported" posture as
    // _framesFromStyles takes for text-align: justify.
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
        // Matches ParagraphAlignment.name exactly, so
        // EditingEngine.pasteRich's AttributeType.align branch can parse
        // it straight back via ParagraphAlignment.values.byName. 'justify'
        // has no ParagraphAlignment counterpart and is left unrecognized
        // rather than silently mapped to something else.
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