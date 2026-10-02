// A link exports as [text](address). The closing marker used to be built without the
// address, so every exported link ended in "(null)".
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  const exporter = MarkdownExporter();

  test('a link exports with its address', () {
    final out = exporter.export('see site now', [
      const TextAttribute(start: 4, end: 8, type: AttributeType.link, value: 'https://example.com/a?b=1'),
    ]);
    expect(out, 'see [site](https://example.com/a?b=1) now');
  });

  test('a bold link keeps both, and a link ending a paragraph is closed there', () {
    final out = exporter.export('go here\nnext', [
      const TextAttribute(start: 3, end: 7, type: AttributeType.link, value: 'https://x.dev'),
      const TextAttribute(start: 3, end: 7, type: AttributeType.bold),
    ]);
    expect(out, contains('](https://x.dev)'));
    expect(out, isNot(contains('(null)')));
    expect(out.split('\n').last, 'next');
  });

  test('a link split over two paragraphs repeats its address on each', () {
    final out = exporter.export('ab\ncd', [
      const TextAttribute(start: 0, end: 5, type: AttributeType.link, value: 'https://x.dev'),
    ]);
    expect('(https://x.dev)'.allMatches(out).length, 2);
    expect(out, isNot(contains('(null)')));
  });

  test('export then import brings the same link back', () {
    final md = exporter.export('a link b', [
      const TextAttribute(start: 2, end: 6, type: AttributeType.link, value: 'https://example.com'),
    ]);
    final back = const MarkdownImporter().parse(md);
    expect(back.text, 'a link b');
    expect(back.attributes.single.value, 'https://example.com');
  });
}
