// Markup as Chrome actually puts it on the clipboard (computed styles inlined on
// every element), taken from a copied kenresoft.com article.
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';

const _reset = 'box-sizing: border-box; border: 0px solid; margin: 0px; padding: 0px;';

String _import(String html) => const HtmlImporter().parse(html).text;

void main() {
  group('Chrome clipboard markup', () {
    test('adjacent pills whose flex container was not copied are separate lines; one pill in a sentence stays inline', () {
      const pill = 'border: 1px solid rgb(200, 200, 200); border-radius: 2.14748e+09px; background-color: rgb(255, 255, 255); padding-inline: 12px;';
      expect(
        _import('<span style="$pill">Scalable Code</span><span style="$pill">Dart</span><span style="$pill">Mobile</span>'),
        'Scalable Code\nDart\nMobile',
      );
      expect(_import('<p>New <span style="$pill">beta</span> feature</p>'), 'New beta feature');
      expect(_import('<p>use <code style="border-radius: 4px; background-color: rgb(240,240,240)">a</code><code style="border-radius: 4px; background-color: rgb(240,240,240)">b</code></p>'), 'use ab');
    });

    test('a list styled as numbered cards (badge, heading, text) is blocks, not "1. 01"', () {
      const html = '<ol><li><span>01</span><h3>Self-hosted</h3><p>It deploys into your account.</p></li>'
          '<li><span>02</span><h3>API-first</h3><p>Content is served over REST.</p></li></ol><p>After</p>';
      expect(_import(html), '01\nSelf-hosted\nIt deploys into your account.\n\n02\nAPI-first\nContent is served over REST.\n\nAfter');
    });

    test('list-style:none items carry no marker either; an ordinary list keeps its numbers', () {
      expect(_import('<ul style="list-style: none"><li style="list-style: none">a</li><li style="list-style: none">b</li></ul>'), 'a\n\nb');
      expect(_import('<ol><li>one</li><li>two</li></ol>'), '  1. one\n  2. two');
    });

    test('children of a display:flex row are separate lines, not run together', () {
      const html = '<!--StartFragment--><div class="meta" style="$_reset display: flex; flex-wrap: wrap; gap: 4px 16px;">'
          '<span style="$_reset color: rgb(29, 78, 216);">Image SEO</span>'
          '<span style="$_reset">September 28, 2026</span>'
          '<span style="$_reset">11 min read</span>'
          '<span style="$_reset">Kenneth Amadi</span></div><!--EndFragment-->';
      expect(_import(html), 'Image SEO\nSeptember 28, 2026\n11 min read\nKenneth Amadi');
    });

    test('grid children too; an inline-flex box (icon + label link) stays in the line', () {
      expect(_import('<div style="display: grid"><span>a</span><span>b</span></div>'), 'a\nb');
      expect(_import('<p>go <a href="https://x.dev" style="display: inline-flex"><span>read</span><span>more</span></a> now</p>'), 'go readmore now');
    });

    test('a plain inline run is still inline', () {
      expect(_import('<p style="$_reset"><span style="$_reset">one</span><span style="$_reset"> two</span></p>'), 'one two');
    });

    test('display:none content is dropped; display:block on a span breaks the line', () {
      expect(_import('<p>shown<span style="display: none">hidden menu</span></p>'), 'shown');
      expect(_import('<div><span style="display: block">a</span><span style="display: block">b</span></div>'), 'a\nb');
    });

    test('computed font-weight 600 and up counts as bold; 500 and normal do not', () {
      final r = const HtmlImporter().parse('<p><span style="font-weight: 600">semi</span> <span style="font-weight: 500">mid</span> <span style="font-weight: 400">reg</span></p>');
      final bold = r.attributes.where((a) => a.type == AttributeType.bold).toList();
      expect(bold.length, 1);
      expect(r.text.substring(bold.first.start, bold.first.end), 'semi');
    });

    test('a shiki-style code block (span per line, newlines between) stays one block with its lines', () {
      const html = '<div class="code-block"><div class="code-block__bar"><span>Dart</span><button type="button">Copy</button></div>'
          '<pre class="shiki" style="$_reset font-family: ui-monospace, monospace;"><code style="$_reset">'
          '<span class="line"><span style="color:#79C0FF">void</span><span> main() {</span></span>\n'
          '<span class="line"><span>  print(1);</span></span>\n'
          '<span class="line"></span>\n'
          '<span class="line"><span>}</span></span></code></pre></div><p>After.</p>';
      final r = const HtmlImporter().parse(html);
      expect(r.text, 'void main() {\n  print(1);\n\n}\nAfter.', reason: 'the Dart caption is the label, not a line');
      final code = r.attributes.where((a) => a.type == AttributeType.header).single;
      expect(r.text.substring(code.start, code.end), 'void main() {\n  print(1);\n\n}');
    });

    test('a site\'s code caption bar becomes the block language, not a stray line of text', () {
      const html = '<p>Run:</p><div class="code-block"><div class="code-block__bar"><span class="code-block__lang">Shell</span>'
          '<button type="button" class="code-block__copy">Copy</button></div>'
          '<pre><code><span class="line">flutter run --profile</span></code></pre></div><p>Then wait.</p>';
      final r = const HtmlImporter().parse(html);
      expect(r.text, 'Run:\n\nflutter run --profile\nThen wait.');
      final code = r.attributes.singleWhere((a) => a.type == AttributeType.header);
      expect(code.value, 'code:shell');
      expect(r.text.substring(code.start, code.end), 'flutter run --profile');
    });

    test('an explicit language-x class wins over the caption; a bar with no word leaves nothing behind', () {
      final a = const HtmlImporter().parse('<div class="code-block"><div class="code-block__bar"><span>Shell</span></div><pre><code class="language-dart">x</code></pre></div>');
      expect(a.attributes.single.value, 'code:dart');
      final b = const HtmlImporter().parse('<div class="code-block"><div class="code-block__bar"><span></span><button>Copy</button></div><pre>y</pre></div>');
      expect(b.text, 'y');
      expect(b.attributes.single.value, 'code');
    });

    test('ordinary text that merely sits in a div is untouched', () {
      expect(const HtmlImporter().parse('<div class="header"><span>Intro</span></div><p>x</p>').text, 'Intro\nx');
    });

    test('a full copied page region: header furniture, article meta, h1, paragraphs, inline code', () {
      const html = '<!--StartFragment--><div style="$_reset display: flex"><span>Image SEO</span><span>11 min read</span></div>'
          '<h1 style="$_reset font-weight: 700;">Your Images Matter</h1>'
          '<p style="$_reset">Someone finds a photo, names it <code style="$_reset">IMG_4827.jpg</code>, and moves on.</p>'
          '<p style="$_reset">That approach is <strong>incomplete</strong>.</p><!--EndFragment-->';
      final r = const HtmlImporter().parse(html);
      expect(r.text, 'Image SEO\n11 min read\n\nYour Images Matter\nSomeone finds a photo, names it IMG_4827.jpg, and moves on.\n\nThat approach is incomplete.');
    });
  });
}
