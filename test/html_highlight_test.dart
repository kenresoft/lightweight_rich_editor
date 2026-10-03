import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/rendering/code_highlighter.dart';

void main() {
  List<String> of(String code, CodeTokenKind kind) =>
      tokenizeCode(code, 'html').where((t) => t.kind == kind).map((t) => code.substring(t.start, t.end)).toList();

  test('tags, attributes, values, doctype and entities are coloured', () {
    const html = '<!DOCTYPE html>\n<a href="x" class=\'y\'>Tom &amp; Jerry</a>';
    expect(of(html, CodeTokenKind.keyword), ['a', 'a']);
    expect(of(html, CodeTokenKind.type), ['<!DOCTYPE html>', 'href', 'class']);
    expect(of(html, CodeTokenKind.string), ['"x"', "'y'"]);
    expect(of(html, CodeTokenKind.literal), ['&amp;']);
  });

  test("an apostrophe in the text between tags does not swallow the closing tag", () {
    const html = "<p>It's text</p>";
    expect(of(html, CodeTokenKind.string), isEmpty);
    expect(of(html, CodeTokenKind.keyword), ['p', 'p']);
  });

  test('an unlabelled snippet that opens with a tag is recognised as html', () {
    expect(guessLanguage('<img src="a.png">'), 'html');
    expect(guessLanguage('<div class="box">\n  <span>hi</span>'), 'html');
    expect(guessLanguage('<script>\nconst a = 1;\nconsole.log(a);\n</script>'), 'html');
    expect(guessLanguage('just some prose < not a tag'), isNull);
  });
}
