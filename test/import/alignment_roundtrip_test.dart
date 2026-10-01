// Paragraph alignment / text direction are stored but not yet rendered per
// paragraph (a single TextField has one textAlign). Importing and exporting must
// at least never corrupt what is stored.
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/export/html_exporter.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';

List<(String, String?)> blocks(EditorDocument d) => [
  for (final r in d.paragraphs.records) (d.text.substring(r.start, r.end), r.alignment?.name ?? r.textDirection?.name),
];

void main() {
  const text = 'left\ncentered\nright\nrtl one\nplain';
  final doc = EditorDocument.fromText(text, const [
    TextAttribute(start: 5, end: 13, type: AttributeType.align, value: 'center'),
    TextAttribute(start: 14, end: 19, type: AttributeType.align, value: 'right'),
    TextAttribute(start: 20, end: 27, type: AttributeType.textDirection, value: 'rtl'),
  ]);

  test('seeded alignment and direction are per paragraph', () {
    expect(blocks(doc), [('left', null), ('centered', 'center'), ('right', 'right'), ('rtl one', 'rtl'), ('plain', null)]);
  });

  test('JSON round trip keeps them', () {
    expect(blocks(EditorDocument.fromJson(doc.toJson())), blocks(doc));
  });

  test('our HTML export re-imports with the same alignment and direction, text unchanged', () {
    final html = const HtmlExporter(marker: true).export(doc.text, doc.exportAttributes());
    final back = const HtmlImporter().parse(html);
    final again = EditorDocument.fromText(back.text, back.attributes);
    expect(again.text, doc.text);
    expect(blocks(again), blocks(doc));
  });

  test('web HTML: text-align left/center/right and dir are read; justify is ignored, not corrupted', () {
    final r = const HtmlImporter().parse('<p style="text-align:center">c</p><p style="text-align:justify">j</p><p dir="rtl">r</p>');
    final d = EditorDocument.fromText(r.text, r.attributes);
    // (the importer's blank lines between paragraphs are empty paragraphs)
    expect(blocks(d).where((b) => b.$1.isNotEmpty), [('c', 'center'), ('j', null), ('r', 'rtl')]);
  });

  test('a code block is never given an alignment by its neighbours', () {
    final r = const HtmlImporter().parse('<div style="text-align:center"><p>title</p><pre>x = 1</pre></div>');
    final d = EditorDocument.fromText(r.text, r.attributes);
    expect(d.paragraphs.records.last.headerLevel, 'code');
  });
}
