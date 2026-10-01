import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/attribute_type.dart';
import '../models/code_block.dart';
import '../models/image_block.dart';
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

// Tracks the nearest enclosing <ul>/<ol>: what marker a <li> emits, its number
// (ordered lists) and its nesting depth. A fresh instance per list, nested ones
// included, so numbering restarts for each.
class _ListContext {
  final bool ordered;
  final int depth;
  int _counter;
  _ListContext(this.ordered, this.depth, {int start = 1}) : _counter = start - 1;
  int next() => ++_counter;

  String get indent => '  ' * depth;
}

// Blank lines a block wants around it. The gap between two blocks is the
// larger of the previous block's `after` and the next block's `before` (like
// collapsed CSS margins), so nested or adjacent blocks never stack breaks and
// a heading is not pushed away from the paragraph it introduces.
class _Margins {
  final int before;
  final int after;
  const _Margins(this.before, this.after);
}

const _flow = _Margins(0, 1); // p, blockquote, pre, lists
const _heading = _Margins(1, 0);
const _plainBlock = _Margins(0, 0); // div, li, tr, ...

const _marginsByTag = <String, _Margins>{
  'p': _flow,
  'blockquote': _flow,
  'pre': _flow,
  'ul': _flow,
  'ol': _flow,
  'hr': _Margins(1, 1),
  'h1': _heading,
  'h2': _heading,
  'h3': _heading,
  'h4': _heading,
  'h5': _heading,
  'h6': _heading,
  'div': _plainBlock,
  'li': _plainBlock,
  'tr': _plainBlock,
  'table': _flow,
  'section': _plainBlock,
  'article': _plainBlock,
  'header': _plainBlock,
  'footer': _plainBlock,
  'main': _plainBlock,
  'figure': _flow,
  'figcaption': _plainBlock,
  'dl': _flow,
  'dt': _plainBlock,
  'dd': _plainBlock,
};

const _skippedTags = {'script', 'style', 'head', 'title', 'noscript', 'template', 'iframe', 'svg', 'button', 'select'};

/// Parses HTML into plain text plus [TextAttribute]s, for pasting content
/// copied from a browser or another rich-text source.
///
/// The import is *semantic*: block structure becomes paragraph structure, and
/// arbitrary site CSS (margins, padding, fonts) is never reproduced.
///
///  * `<p>`, `<blockquote>`, `<pre>`, lists: one blank line after them;
///    headings: one blank line before them, none after; `<div>`/`<li>`/
///    `<section>`...: a plain line break. Adjacent and nested blocks collapse
///    to a single gap, never stacking.
///  * `<br>`: an explicit line break (a trailing one in a block is ignored,
///    as browsers do).
///  * Whitespace is collapsed like a browser: runs become one space, spaces
///    that matter between inline elements are kept (`<b>a</b> <i>b</i>`), and
///    whitespace-only nodes between blocks (pretty-printed source) vanish.
///  * `<pre>` text is kept exactly — indentation, blank lines — as a block
///    level code block (`<code class="language-x">` supplies the label).
///  * Inline: `<b>`/`<strong>`, `<i>`/`<em>`, `<u>`, `<s>`/`<strike>`/`<del>`,
///    `<code>`, `<a href>`, and inline `style` bold/italic/underline/
///    line-through/text-align; `<h1>`–`<h6>` (h3 and deeper collapse to h3).
///  * `<li>` inside `<ul>`/`<ol>` gets a literal `'  - '`/`'  N. '` prefix
///    (real characters), with 2 more spaces per nesting level.
///  * `<blockquote>` lines get a literal `'> '` prefix, as in Markdown.
///  * `<script>`/`<style>`/`<head>` and the like are skipped.
class HtmlImporter {
  /// Blank lines left after a paragraph-like block (`<p>`, `<blockquote>`,
  /// lists, `<pre>`...). `1` (the default) keeps pasted articles readable;
  /// `0` makes every block just a line break.
  const HtmlImporter({this.paragraphGap = 1});

  final int paragraphGap;

  /// Parses [htmlString]. With [images] on, each `<img>` (a web address or an
  /// inline `data:` URI) becomes a block of blank placeholder rows and is listed
  /// in the result's `images`, for the caller to fetch and fill in.
  ({String text, List<TextAttribute> attributes, List<ImportedImage> images}) parse(String htmlString, {bool images = false}) {
    // Our own export (see HtmlExporter.marker) is re-imported line for line.
    final exact = htmlString.contains(_generatorMarker);
    final document = html_parser.parse(_fragmentOf(htmlString));
    final body = document.body;
    final run = _Run(exact ? 0 : paragraphGap, tightHeadings: exact, importColors: exact, includeImages: images);
    if (body != null) run.walk(body, const [], null);
    return run.finish();
  }
}

// What was actually copied. Browsers wrap the selection in
// `<!--StartFragment-->`/`<!--EndFragment-->`, and the Windows clipboard's
// "HTML Format" prepends a `Version:0.9 StartHTML:... EndHTML:...` header that
// is not markup and would otherwise be pasted as text.
const _generatorMarker = 'name="generator" content="lightweight_rich_editor"';

String _fragmentOf(String html) {
  final start = html.indexOf('<!--StartFragment-->');
  if (start != -1) {
    final end = html.indexOf('<!--EndFragment-->', start);
    return html.substring(start + '<!--StartFragment-->'.length, end == -1 ? html.length : end);
  }
  if (html.startsWith('Version:')) {
    final firstTag = html.indexOf('<');
    return firstTag == -1 ? '' : html.substring(firstTag);
  }
  return html;
}

class _Run {
  _Run(this.paragraphGap, {this.tightHeadings = false, this.importColors = false, this.includeImages = false});

  final bool includeImages;
  final List<ImportedImage> _images = [];

  final int paragraphGap;
  final bool tightHeadings;

  // Text colour is imported only from our own export. A copied web page puts
  // its body text colour on nearly every element, and importing that would
  // paint pasted articles in a fixed grey that vanishes in a dark theme.
  final bool importColors;
  int _liDepth = 0;
  final StringBuffer _buffer = StringBuffer();
  final List<TextAttribute> _attributes = [];
  final List<TextAttribute> _codeBlocks = [];

  int _length = 0;
  int _lastCode = 0x0A; // last code unit written ('\n' = at line start)

  // Newlines owed before the next content (0 = none). Block boundaries raise
  // it to `1 + gap`; `<br>` adds one. It is only ever written when content
  // follows, so leading/trailing breaks cost nothing.
  int _sep = 0;

  // Whether [_sep] was last raised by a block boundary (not by a `<br>`).
  bool _gapFromBoundary = false;

  // An inter-word space seen but not yet written, with the formatting frames
  // of the node it came from; dropped if a line break wins.
  bool _pendingSpace = false;
  List<_StyleFrame> _pendingSpaceStack = const [];

  // Set right after a list marker is written, so a block wrapper directly
  // inside the <li> (Google Docs' `<li><p>text</p></li>`) does not break the
  // line between the marker and its text.
  int _glueAt = -1;

  int _quoteDepth = 0;

  bool get _atLineStart => _lastCode == 0x0A;

  void _write(String s) {
    if (s.isEmpty) return;
    _buffer.write(s);
    _length += s.length;
    _lastCode = s.codeUnitAt(s.length - 1);
  }

  // A block boundary wanting [gap] blank lines.
  void _boundary(int gap) {
    if (_length == 0 || _length == _glueAt) return;
    final wanted = 1 + gap;
    if (wanted > _sep) {
      _sep = wanted;
      _gapFromBoundary = true;
    }
    _pendingSpace = false;
  }

  // Everything that must precede real content: owed newlines, a pending space,
  // and the '> ' of an enclosing blockquote at a line start.
  void _beginContent() {
    if (_length > 0 && _sep > 0) {
      _write('\n' * _sep);
      _sep = 0;
      _pendingSpace = false;
    } else if (_pendingSpace && _length > 0 && !_atLineStart && _lastCode != 0x20) {
      final start = _length;
      _write(' ');
      for (final f in _pendingSpaceStack) {
        _attributes.add(TextAttribute(start: start, end: _length, type: f.type, value: f.value));
      }
    }
    _pendingSpace = false;
    _sep = 0;
    if (_quoteDepth > 0 && _atLineStart) _write('> ' * _quoteDepth);
  }

  void walk(dom.Node node, List<_StyleFrame> stack, _ListContext? list) {
    if (node is dom.Text) {
      _text(node.text, stack);
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName;
    if (tag == null || _skippedTags.contains(tag)) return;
    if (tag == 'br') {
      if (_length > 0) {
        // A spacer `<br>` straight after a block that already owes its blank
        // line (`</p><br><p>`, `</ul><br>`) is that same blank line, not a
        // second one — otherwise re-importing what we export grows by a line
        // per cycle. Only the first `<br>` is absorbed, so deliberate runs of
        // them still count.
        if (_gapFromBoundary && _sep >= 1 + paragraphGap && paragraphGap > 0) {
          _gapFromBoundary = false;
        } else {
          _sep += 1;
          _gapFromBoundary = false;
        }
        _pendingSpace = false;
      }
      return;
    }
    if (tag == 'hr') {
      _boundary(1);
      _beginContent();
      _write('---');
      _boundary(1);
      return;
    }
    if (tag == 'pre') {
      _pre(node);
      return;
    }
    if (node.attributes.containsKey('data-rich-image')) {
      _imageBlock(node);
      return;
    }
    if (tag == 'img') {
      _remoteImage(node);
      return;
    }
    if (tag == 'td' || tag == 'th') {
      // Cells of a row stay on one line, separated by a space.
      _pendingSpace = _length > 0;
      _pendingSpaceStack = stack;
      for (final c in node.nodes) {
        walk(c, stack, list);
      }
      _pendingSpace = _length > 0;
      return;
    }

    // The caption bar sites put above a code block ("Dart", "Shell" + a Copy
    // button) is the block's label, not a line of the note: it becomes the
    // block's language instead of being pasted as stray text.
    final barLang = _codeBarLanguage(node);
    if (barLang != null) {
      _pendingCodeLanguage = barLang;
      return;
    }
    // Pills/badges/tag chips side by side (a tag list, a meta row) are separate
    // items on the page, set apart by the container's flex gap. When that
    // container is not part of what was copied the pills touch in the markup,
    // so a pill that directly follows another pill starts a new line.
    if (_isChip(node) && _previousIsChip(node)) _boundary(0);
    final display = _displayOf(node);
    if (display == 'none') return; // hidden on the page (menus, duplicates) is hidden in the note
    var margins = _marginsFor(tag);
    // Layout display is the one piece of CSS that decides where lines break:
    // Chrome serialises computed styles into the clipboard, and the children of
    // a flex/grid container are blocks (its plain-text copy puts each on its own
    // line), as is an element that is itself `display:block`. Everything else
    // about the page's styling is still ignored.
    if (margins == null && (_isBlockDisplay(display) || _isFlexItem(node))) margins = _plainBlock;
    var childList = list;
    if (tag == 'ul') {
      childList = _ListContext(false, (list?.depth ?? 0) + 1);
    } else if (tag == 'ol') {
      final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      childList = _ListContext(true, (list?.depth ?? 0) + 1, start: start);
    }

    if (tag == 'li' && list != null && node.text.trim().isEmpty) return; // an empty bullet is noise

    // A "card" item (a list the site styled as a grid of cards: no marker, a
    // heading inside) is not a list entry. It becomes its own block, set off by a
    // blank line, with no bullet or number: the site's own badge ("01") is its
    // visible numbering, and a second "1." would only double it.
    final isCard = tag == 'li' && list != null && _isCardItem(node);
    if (isCard) margins = _Margins(paragraphGap, paragraphGap);

    if (margins != null) {
      // A nested list sits tight under its parent item.
      final nestedList = (tag == 'ul' || tag == 'ol') && list != null;
      _boundary(nestedList ? 0 : margins.before);
    }

    if (tag == 'li' && list != null && !isCard) {
      final ownText = node.text.trimLeft();
      if (listPrefixLength(ownText, 0) == 0) {
        _beginContent();
        _write(list.ordered ? '${list.indent}${list.next()}. ' : '${list.indent}- ');
        _glueAt = _length;
      } else if (list.ordered) {
        list.next();
      }
    }

    var inner = stack;
    final frame = _frameFor(tag);
    if (frame != null) inner = [...inner, frame];
    inner = [...inner, ..._framesFromStyles(node)];
    final dir = node.attributes['dir'];
    if (dir == 'rtl' || dir == 'ltr') inner = [...inner, _StyleFrame(AttributeType.textDirection, dir)];
    if (tag == 'a') {
      final href = node.attributes['href'];
      if (href != null && href.isNotEmpty) inner = [...inner, _StyleFrame(AttributeType.link, href)];
    }

    if (tag == 'blockquote') _quoteDepth++;
    if (tag == 'li') _liDepth++;
    for (final child in node.nodes) {
      walk(child, inner, childList);
    }
    if (tag == 'li') _liDepth--;
    if (tag == 'blockquote') _quoteDepth--;

    if (margins != null) {
      final nestedList = (tag == 'ul' || tag == 'ol') && list != null;
      _boundary(nestedList ? 0 : margins.after);
    }
  }

  static final RegExp _radius = RegExp(r'border-radius\s*:\s*(?!0(?:px)?\s*[;"])[\d.]', caseSensitive: false);
  static final RegExp _filled = RegExp(r'background-color\s*:\s*(?!rgba\(0,\s*0,\s*0,\s*0\))(?!transparent)[a-z]', caseSensitive: false);
  static final RegExp _outlined = RegExp(r'(?:^|;)\s*border\s*:\s*(?!0(?:px)?\b)[\d.]+px', caseSensitive: false);

  // An inline element styled as a pill: rounded, and filled or outlined. Not
  // `code`/`kbd` (those are inline code, which stays in the line).
  static bool _isChip(dom.Element e) {
    final tag = e.localName;
    if (tag == 'code' || tag == 'kbd' || tag == 'pre' || tag == 'mark') return false;
    final style = e.attributes['style'];
    if (style == null || !_radius.hasMatch(style)) return false;
    return _filled.hasMatch(style) || _outlined.hasMatch(style);
  }

  // The nearest preceding sibling element (skipping whitespace-only text) is a pill.
  static bool _previousIsChip(dom.Element e) {
    final siblings = e.parentNode?.nodes;
    if (siblings == null) return false;
    var i = siblings.indexOf(e) - 1;
    while (i >= 0 && siblings[i] is dom.Text && (siblings[i] as dom.Text).text.trim().isEmpty) {
      i--;
    }
    return i >= 0 && siblings[i] is dom.Element && _isChip(siblings[i] as dom.Element);
  }

  static final RegExp _noListStyle = RegExp(r'list-style(?:-type)?\s*:\s*none', caseSensitive: false);

  static bool _isCardItem(dom.Element li) {
    if (_noListStyle.hasMatch(li.attributes['style'] ?? '')) return true;
    for (final c in li.children) {
      final n = c.localName;
      if (n != null && n.length == 2 && n[0] == 'h' && '123456'.contains(n[1])) return true;
    }
    return false;
  }

  String? _pendingCodeLanguage;

  static final RegExp _codeBarClass = RegExp(r'code|highlight|snippet', caseSensitive: false);
  static final RegExp _barWord = RegExp(r'bar|header|toolbar|title|label|lang|caption', caseSensitive: false);

  // An element classed like a code block's caption bar whose visible text is one
  // short language-like word; returns that word normalised, else null.
  static String? _codeBarLanguage(dom.Element e) {
    final cls = e.attributes['class'];
    if (cls == null || !_codeBarClass.hasMatch(cls) || !_barWord.hasMatch(cls)) return null;
    final buf = StringBuffer();
    void collect(dom.Node n) {
      if (n is dom.Text) {
        buf.write(n.text);
      } else if (n is dom.Element && !_skippedTags.contains(n.localName)) {
        n.nodes.forEach(collect);
      }
    }
    collect(e);
    final text = buf.toString().trim();
    if (text.isEmpty || text.length > 20 || RegExp(r'\s').hasMatch(text)) return null;
    return normalizeCodeLanguage(text);
  }

  static const _blockDisplays = {'block', 'flex', 'grid', 'list-item', 'table', 'flow-root'};

  static String? _displayOf(dom.Element e) {
    final style = e.attributes['style'];
    if (style == null || !style.contains('display')) return null;
    String? last;
    for (final m in RegExp(r'(?:^|;)\s*display\s*:\s*([a-z-]+)', caseSensitive: false).allMatches(style)) {
      last = m.group(1)!.toLowerCase();
    }
    return last;
  }

  static bool _isBlockDisplay(String? d) => d != null && _blockDisplays.contains(d);

  static bool _isFlexItem(dom.Element e) {
    final parent = e.parent;
    if (parent == null) return false;
    final d = _displayOf(parent);
    return d == 'flex' || d == 'grid'; // inline-flex boxes sit in the line, their children with them
  }

  // Margins for [tag]: paragraph-like blocks use [paragraphGap], and inside a
  // list item nothing adds blank lines (items stay tight).
  _Margins? _marginsFor(String tag) {
    final m = _marginsByTag[tag];
    if (m == null) return null;
    if (_liDepth > 0) return _Margins(m.before > 0 && tag.startsWith('h') ? 0 : m.before, 0);
    if (identical(m, _flow)) return _Margins(0, paragraphGap);
    if (tag == 'hr') return _Margins(paragraphGap, paragraphGap);
    if (identical(m, _heading)) return _Margins(tightHeadings ? 0 : paragraphGap, 0);
    return m;
  }

  void _text(String raw, List<_StyleFrame> stack) {
    // ASCII whitespace collapses; a non-breaking space is content, not
    // collapsible whitespace, but is written as an ordinary space.
    final collapsed = raw.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
    if (collapsed.isEmpty) return;
    final leading = collapsed.startsWith(' ');
    final trailing = collapsed.length > 1 && collapsed.endsWith(' ');
    final core = collapsed.trim().replaceAll(' ', ' ');
    if (core.isEmpty && collapsed.trim().isEmpty) {
      if (_length > 0) {
        _pendingSpace = true;
        _pendingSpaceStack = stack;
      }
      return;
    }
    if (leading && _length > 0) {
      _pendingSpace = true;
      _pendingSpaceStack = stack;
    }
    _beginContent();
    final start = _length;
    _write(core);
    for (final f in stack) {
      _attributes.add(TextAttribute(start: start, end: _length, type: f.type, value: f.value));
    }
    if (!stack.any((f) => f.type == AttributeType.link)) {
      for (final u in detectAllUrls(core)) {
        _attributes.add(TextAttribute(start: start + u.start, end: start + u.end, type: AttributeType.link, value: u.href));
      }
    }
    if (trailing) {
      _pendingSpace = true;
      _pendingSpaceStack = stack;
    }
  }

  // A <pre> becomes a block-level code block: its text exactly as written,
  // one paragraph per line, labelled by a `language-x` class if there is one.
  void _pre(dom.Element pre) {
    final buf = StringBuffer();
    _collectPre(pre, buf);
    var code = buf.toString().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (code.startsWith('\n')) code = code.substring(1); // the first newline of <pre> is not content
    while (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }
    if (code.trim().isEmpty) return;

    final lang = _languageOf(pre) ?? _pendingCodeLanguage;
    _pendingCodeLanguage = null;
    _boundary(0);
    _beginContent();
    final start = _length;
    _write(code);
    _codeBlocks.add(TextAttribute(
      start: start,
      end: _length,
      type: AttributeType.header,
      value: codeBlockLevelFor(lang),
    ));
    // Tight after the block: the code background separates it visually, and a
    // blank line here would make our own <pre> export grow one line per paste.
    _boundary(0);
  }

  // An image block this editor exported: its rows come back as blank lines
  // flagged with the block level.
  void _imageBlock(dom.Element e) {
    final level = e.attributes['data-rich-image'] ?? '';
    if (imageIdOf(level) == null) return;
    final rows = (int.tryParse(e.attributes['data-rows'] ?? '') ?? minImageRows).clamp(2, maxImageRows);
    _boundary(0);
    _beginContent();
    final start = _length;
    _write('\n' * (rows - 1));
    _codeBlocks.add(TextAttribute(start: start, end: _length, type: AttributeType.header, value: level));
    _boundary(0);
  }

  // An `<img>` of a page: a block of blank rows, to be filled with the picture
  // once its bytes are fetched. Icons, emoji and tracking pixels (tiny or marked
  // as such) are not pictures worth a block.
  void _remoteImage(dom.Element e) {
    if (!includeImages || _images.length >= maxImportedImages) return;
    var src = (e.attributes['src'] ?? e.attributes['data-src'] ?? '').trim();
    if (src.isEmpty) {
      final srcset = (e.attributes['srcset'] ?? '').trim();
      if (srcset.isNotEmpty) src = srcset.split(',').first.trim().split(RegExp(r'\s+')).first;
    }
    if (!isImportableImageSource(src)) return;
    final w = int.tryParse((e.attributes['width'] ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
    final h = int.tryParse((e.attributes['height'] ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
    if ((w != null && w < 48) || (h != null && h < 48)) return;
    if (RegExp(r'emoji|emoticon|avatar|favicon|spacer|pixel', caseSensitive: false).hasMatch('${e.attributes['class'] ?? ''} $src')) return;
    final rows = (w != null && h != null) ? rowsForImage(w, h) : 6;
    final level = imageLevelFor(pendingImageId, newImageInstance());
    _boundary(0);
    _beginContent();
    final start = _length;
    _write('\n' * (rows - 1));
    _codeBlocks.add(TextAttribute(start: start, end: _length, type: AttributeType.header, value: level));
    _images.add(ImportedImage(level: level, source: src, alt: (e.attributes['alt'] ?? '').trim()));
    _boundary(0);
  }

  void _collectPre(dom.Node node, StringBuffer out) {
    if (node is dom.Text) {
      out.write(node.text);
    } else if (node is dom.Element) {
      final tag = node.localName;
      if (tag == 'br') {
        out.write('\n');
        return;
      }
      if (tag == 'script' || tag == 'style') return;
      for (final c in node.nodes) {
        _collectPre(c, out);
      }
      if ((tag == 'div' || tag == 'p') && !out.toString().endsWith('\n')) out.write('\n');
    }
  }

  String? _languageOf(dom.Element pre) {
    String? fromClass(String? classes) {
      if (classes == null) return null;
      for (final c in classes.split(RegExp(r'\s+'))) {
        for (final prefix in const ['language-', 'lang-', 'highlight-source-', 'brush:']) {
          if (c.startsWith(prefix)) return normalizeCodeLanguage(c.substring(prefix.length));
        }
      }
      return null;
    }

    final direct = fromClass(pre.attributes['class']) ?? normalizeCodeLanguage(pre.attributes['data-lang'] ?? pre.attributes['data-language']);
    if (direct != null) return direct;
    final code = pre.querySelector('code');
    if (code != null) {
      final inner = fromClass(code.attributes['class']) ?? normalizeCodeLanguage(code.attributes['data-lang']);
      if (inner != null) return inner;
    }
    // GitHub: <div class="highlight highlight-source-dart"><pre>
    final parent = pre.parent;
    return parent == null ? null : fromClass(parent.attributes['class']);
  }

  ({String text, List<TextAttribute> attributes, List<ImportedImage> images}) finish() {
    // Trailing owed newlines/space are simply never written.
    return (
      text: _buffer.toString(),
      attributes: [..._mergeAttributes(_attributes), ..._codeBlocks],
      images: _images,
    );
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

      if (property == 'font-weight' && _isBoldWeight(value)) {
        frames.add(const _StyleFrame(AttributeType.bold, null));
      } else if (property == 'font-style' && value == 'italic') {
        frames.add(const _StyleFrame(AttributeType.italic, null));
      } else if (property == 'text-decoration' || property == 'text-decoration-line') {
        if (value.contains('underline')) {
          frames.add(const _StyleFrame(AttributeType.underline, null));
        }
        if (value.contains('line-through')) {
          frames.add(const _StyleFrame(AttributeType.strikethrough, null));
        }
      } else if (property == 'color' && importColors) {
        final argb = _parseCssColor(value);
        if (argb != null) frames.add(_StyleFrame(AttributeType.color, argb));
      } else if (property == 'text-align' && (value == 'left' || value == 'center' || value == 'right')) {
        // value must match ParagraphAlignment.name; 'justify' has no
        // counterpart and is left unrecognized.
        frames.add(_StyleFrame(AttributeType.align, value));
      }
    }
    return frames;
  }

  // CSS treats 600 and up (and `bolder`) as bold.
  bool _isBoldWeight(String v) {
    if (v == 'bold' || v == 'bolder') return true;
    final n = int.tryParse(v);
    return n != null && n >= 600;
  }

  // #rgb / #rrggbb only: the one form our own export writes.
  int? _parseCssColor(String v) {
    final m = RegExp(r'^#([0-9a-f]{6}|[0-9a-f]{3})$').firstMatch(v);
    if (m == null) return null;
    var hex = m.group(1)!;
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    return 0xFF000000 | int.parse(hex, radix: 16);
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

  _StyleFrame? _frameFor(String tag) {
    switch (tag) {
      case 'b':
      case 'strong':
        return const _StyleFrame(AttributeType.bold, null);
      case 'i':
      case 'em':
      case 'cite':
        return const _StyleFrame(AttributeType.italic, null);
      case 'u':
        return const _StyleFrame(AttributeType.underline, null);
      case 's':
      case 'strike':
      case 'del':
        return const _StyleFrame(AttributeType.strikethrough, null);
      case 'code':
      case 'kbd':
      case 'samp':
        return const _StyleFrame(AttributeType.code, null);
      case 'mark':
        return const _StyleFrame(AttributeType.highlight, null);
      case 'h1':
        return const _StyleFrame(AttributeType.header, 'h1');
      case 'h2':
        return const _StyleFrame(AttributeType.header, 'h2');
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return const _StyleFrame(AttributeType.header, 'h3');
      default:
        return null;
    }
  }
}
