// Markup as Chrome actually puts it on the clipboard (computed styles inlined on
// every element), taken from a copied kenresoft.com article.
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';

const _reset = 'box-sizing: border-box; border: 0px solid; margin: 0px; padding: 0px;';

String _import(String html) => const HtmlImporter().parse(html).text;

void main() {
  group('Chrome clipboard markup', () {
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
      expect(r.text, 'Dart\nvoid main() {\n  print(1);\n\n}\nAfter.');
      final code = r.attributes.where((a) => a.type == AttributeType.header).single;
      expect(r.text.substring(code.start, code.end), 'void main() {\n  print(1);\n\n}');
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
