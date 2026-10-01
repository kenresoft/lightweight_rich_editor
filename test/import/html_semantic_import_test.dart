// Semantic HTML import: block structure becomes paragraph structure; CSS never
// does. Includes realistic browser-copy HTML and the whole paste path
// (clipboard channel -> ClipboardManager -> document -> rendered span).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/clipboard/clipboard_manager.dart';
import 'package:lightweight_rich_editor/src/commands/command_dispatcher.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_selection.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/history/history_manager.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';

const importer = HtmlImporter();

String t(String html) => importer.parse(html).text;

/// A realistic Chrome selection copy (fragment markers, inline styles, pretty
/// printed source, nested blocks, a list, a quote, a code sample).
const article = '''<html><body><!--StartFragment--><div class="post-body" style="color: rgb(33, 37, 41); font-family: Inter;">
  <h2 style="font-weight: 700;">Why notebooks matter</h2>
  <p>First paragraph with <a href="https://kenresoft.com/blog/x">a link</a>, <strong>bold</strong> and <em>italic</em>
     text that was wrapped in the source.</p>
  <p>Second paragraph<br>after a line break.</p>
  <ul>
    <li>One</li>
    <li>Two
      <ul><li>Nested</li></ul>
    </li>
  </ul>
  <blockquote><p>A quoted line.</p></blockquote>
  <pre><code class="language-dart">void main() {
  print('hi');

}
</code></pre>
  <p>Closing paragraph.</p>
</div><!--EndFragment--></body></html>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('paragraph structure', () {
    test('adjacent paragraphs are separated by exactly one blank line', () {
      expect(t('<p>One</p><p>Two</p><p>Three</p>'), 'One\n\nTwo\n\nThree');
    });

    test('whitespace-only nodes between blocks are ignored', () {
      expect(t('<div>\n  <p>One</p>\n\n  <p>Two</p>\n</div>'), 'One\n\nTwo');
      expect(t('<p>One</p>   \n\t  <p>Two</p>'), 'One\n\nTwo');
    });

    test('nested blocks do not stack breaks', () {
      expect(t('<div><div><p>One</p></div></div><div><p>Two</p></div>'), 'One\n\nTwo');
      expect(t('<blockquote><p>One</p></blockquote><p>Two</p>'), '> One\n\nTwo');
    });

    test('a heading hugs what it introduces and gets space before it', () {
      expect(t('<p>Intro</p><h2>Title</h2><p>Body</p>'), 'Intro\n\nTitle\nBody');
      expect(t('<h1>A</h1><h2>B</h2>'), 'A\n\nB'); // a heading always gets space before it
    });

    test('div is a plain line break', () {
      expect(t('<div>One</div><div>Two</div>'), 'One\nTwo');
    });

    test('<br> is an explicit line break; a trailing one in a block is ignored', () {
      expect(t('<p>One<br>Two</p>'), 'One\nTwo');
      expect(t('<p>One<br></p><p>Two</p>'), 'One\n\nTwo');
      expect(t('<p>One<br><br>Two</p>'), 'One\n\nTwo');
      expect(t('<br><p>One</p>'), 'One');
    });

    test('paragraphGap: 0 turns paragraphs into plain line breaks', () {
      expect(const HtmlImporter(paragraphGap: 0).parse('<p>One</p><p>Two</p>').text, 'One\nTwo');
    });
  });

  group('inline spacing', () {
    test('meaningful spaces between inline elements survive', () {
      expect(t('<p><b>a</b> <i>b</i></p>'), 'a b');
      expect(t('<p>Hello <b>big</b> <i>wide</i> world</p>'), 'Hello big wide world');
      expect(t('<p>x<b>y</b>z</p>'), 'xyz');
    });

    test('runs of source whitespace collapse to one space; edges are trimmed', () {
      expect(t('<p>  one\n   two\t three  </p>'), 'one two three');
    });

    test('a space is never doubled or left dangling at a line end', () {
      expect(t('<p>end </p><p> start</p>'), 'end\n\nstart');
      expect(t('<p>a <b> </b> b</p>'), 'a b');
    });

    test('a space between two underlined words keeps its underline', () {
      final r = importer.parse('<u>one <b>two</b></u>');
      expect(r.text, 'one two');
      final u = r.attributes.singleWhere((a) => a.type == AttributeType.underline);
      expect([u.start, u.end], [0, 7]);
    });

    test('non-breaking spaces are kept as spaces and not collapsed', () {
      expect(t('<p>a&nbsp;&nbsp;b</p>'), 'a  b');
    });

    test('span offsets stay correct after breaks and gaps', () {
      final r = importer.parse('<p>aa</p><p>b<b>cc</b></p>');
      expect(r.text, 'aa\n\nbcc');
      final b = r.attributes.singleWhere((a) => a.type == AttributeType.bold);
      expect(r.text.substring(b.start, b.end), 'cc');
    });
  });

  group('lists', () {
    test('items are tight and the list is separated from prose by a gap', () {
      expect(t('<p>Intro</p><ul><li>One</li><li>Two</li></ul><p>After</p>'), 'Intro\n\n  - One\n  - Two\n\nAfter');
    });

    test('nested lists indent and stay tight', () {
      expect(t('<ul><li>One<ul><li>Sub</li></ul></li><li>Two</li></ul>'), '  - One\n    - Sub\n  - Two');
    });

    test('ordered lists number from <ol start>', () {
      expect(t('<ol start="3"><li>c</li><li>d</li></ol>'), '  3. c\n  4. d');
    });

    test('paragraphs inside items do not add blank lines', () {
      expect(t('<ul><li><p>One</p></li><li><p>Two</p></li></ul>'), '  - One\n  - Two');
    });

    test('empty items are dropped', () {
      expect(t('<ul><li>One</li><li> </li><li>Two</li></ul>'), '  - One\n  - Two');
    });
  });

  group('blockquote, pre, hr', () {
    test('blockquote lines carry a literal "> " prefix', () {
      expect(t('<blockquote>One<br>Two</blockquote>'), '> One\n> Two');
    });

    test('<pre> is preserved exactly and becomes a code block', () {
      final r = importer.parse('<pre>  indented\n\n    more\n</pre>');
      expect(r.text, '  indented\n\n    more');
      final code = r.attributes.singleWhere((a) => a.type == AttributeType.header);
      expect(code.value, 'code');
      expect([code.start, code.end], [0, r.text.length]);
    });

    test('<pre><code class="language-dart"> labels the block; inline markup inside is flattened', () {
      final r = importer.parse('<pre><code class="language-dart">var <b>x</b> = 1;\nprint(x);</code></pre>');
      expect(r.text, 'var x = 1;\nprint(x);');
      expect(r.attributes.where((a) => a.type == AttributeType.bold), isEmpty);
      expect(r.attributes.single.value, 'code:dart');
    });

    test('code text keeps < > & and is not treated as markup', () {
      final r = importer.parse('<pre><code>if (a &lt; b &amp;&amp; c &gt; d) {}</code></pre>');
      expect(r.text, 'if (a < b && c > d) {}');
    });

    test('<pre> separates from surrounding paragraphs by a gap', () {
      // Gap before (from the paragraph); tight after — the code background
      // separates it, and a blank line there would make our own export grow.
      expect(t('<p>Before</p><pre>x</pre><p>After</p>'), 'Before\n\nx\nAfter');
    });

    test('inline <code> stays an inline attribute', () {
      final r = importer.parse('<p>use <code>TextEditingController</code> here</p>');
      expect(r.text, 'use TextEditingController here');
      expect(r.attributes.single.type, AttributeType.code);
    });

    test('<hr> becomes a horizontal rule line', () {
      expect(t('<p>a</p><hr><p>b</p>'), 'a\n\n---\n\nb');
    });
  });

  group('clipboard framing', () {
    test('Windows CF_HTML header is not pasted as text', () {
      const cf = 'Version:0.9\r\nStartHTML:00000097\r\nEndHTML:00000200\r\nStartFragment:00000131\r\nEndFragment:00000164\r\n'
          '<html><body>\r\n<!--StartFragment--><p>Hello</p><!--EndFragment-->\r\n</body></html>';
      expect(t(cf), 'Hello');
      expect(t('Version:0.9\r\nStartHTML:1\r\n<html><body><p>Hi</p></body></html>'), 'Hi');
    });

    test('only the fragment between the markers is imported', () {
      expect(t('<html><body><p>outside</p><!--StartFragment--><p>in</p><!--EndFragment--><p>out</p></body></html>'), 'in');
    });

    test('scripts, styles and comments are skipped', () {
      expect(t('<p>a</p><script>x()</script><style>p{}</style><!-- c --><p>b</p>'), 'a\n\nb');
    });
  });

  group('realistic article', () {
    test('structure of a copied blog article', () {
      final r = importer.parse(article);
      expect(
        r.text,
        'Why notebooks matter\n'
        'First paragraph with a link, bold and italic text that was wrapped in the source.\n'
        '\n'
        'Second paragraph\n'
        'after a line break.\n'
        '\n'
        '  - One\n'
        '  - Two\n'
        '    - Nested\n'
        '\n'
        '> A quoted line.\n'
        '\n'
        'void main() {\n'
        "  print('hi');\n"
        '\n'
        '}\n'
        'Closing paragraph.',
      );
      final byType = {for (final a in r.attributes) a.type: a};
      expect(r.text.substring(byType[AttributeType.link]!.start, byType[AttributeType.link]!.end), 'a link');
      expect(byType[AttributeType.link]!.value, 'https://kenresoft.com/blog/x');
      expect(r.text.substring(byType[AttributeType.bold]!.start, byType[AttributeType.bold]!.end), 'bold');
      expect(r.text.substring(byType[AttributeType.italic]!.start, byType[AttributeType.italic]!.end), 'italic');
      final headers = r.attributes.where((a) => a.type == AttributeType.header).toList();
      expect(headers.map((h) => h.value), containsAll(['h2', 'code:dart']));
    });
  });

  group('whole paste path: clipboard -> document -> render', () {
    const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');

    late EditorDocument document;
    late ClipboardManager clipboard;
    late HistoryManager history;

    setUp(() {
      document = EditorDocument();
      final engine = EditingEngine(document: document, transactions: TransactionManager(() {}));
      history = HistoryManager(engine: engine);
      clipboard = ClipboardManager(document: document, commands: CommandDispatcher(engine: engine, history: history));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getData') {
          // What a browser puts on the clipboard: the HTML and its flattened plain text.
          return {'text': 'Why notebooks matter First paragraph...', 'html': article};
        }
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('the pasted document has the article structure, spans and block metadata', () async {
      await clipboard.paste(const EditorSelection.collapsed(0));
      final lines = document.text.split('\n');
      expect(lines.first, 'Why notebooks matter');
      expect(lines, contains('  - Two'));
      expect(lines, contains('> A quoted line.'));
      expect(document.paragraphs.records.first.headerLevel, 'h2');
      final codeLine = document.paragraphs.paragraphAt(document.text.indexOf("print('hi');"));
      expect(codeLine!.headerLevel, 'code:dart');
      // the blank line inside the code is still part of the block
      final blank = document.paragraphs.paragraphAt(document.text.indexOf('print') + "print('hi');\n".length);
      expect(blank!.headerLevel, 'code:dart');
      expect(blank.start, blank.end);
    });

    test('one undo removes the whole paste', () async {
      await clipboard.paste(const EditorSelection.collapsed(0));
      history.undo();
      expect(document.text, isEmpty);
    });

    test('the pasted document renders: paragraphs spaced, code monospace, links styled', () async {
      await clipboard.paste(const EditorSelection.collapsed(0));
      final renderer = TextSpanRenderer(theme: const RichTextRenderTheme(lineHeight: 30));
      final span = renderer.renderSpan(document, style: const TextStyle(fontSize: 16));
      // (bullet markers are drawn as dots, same length)
      expect(span.toPlainText().replaceAll('•', '-'), document.text);
      final runs = span.children!.cast<TextSpan>();
      final codeRun = runs.firstWhere((r) => r.text!.contains('print'));
      expect(codeRun.style!.fontFamily, 'monospace');
      final linkRun = runs.firstWhere((r) => r.text == 'a link');
      expect(linkRun.style!.decoration, TextDecoration.underline);
    });
  });
}
