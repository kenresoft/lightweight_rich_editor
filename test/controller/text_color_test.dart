// Text colour: apply, change, remove, mixed selections, collapsed-caret typing,
// undo/redo, clear formatting, copy/paste and import/export.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/clipboard/in_memory_rich_clipboard_delegate.dart';
import 'package:lightweight_rich_editor/src/export/html_exporter.dart';
import 'package:lightweight_rich_editor/src/export/markdown_exporter.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';

const red = 0xFFD32F2F;
const blue = 0xFF1976D2;

RichEditorController make([String text = 'hello world']) => RichEditorController(text: text);

List<(int, int, int)> colors(RichEditorController c) => [
  for (final a in c.document.attributes.where((a) => a.type == AttributeType.color)) (a.start, a.end, a.value as int),
]..sort((a, b) => a.$1.compareTo(b.$1));

Color? rendered(RichEditorController c, int offset) {
  final span = c.renderer.renderSpan(c.document, style: const TextStyle(fontSize: 16, color: Color(0xFF111111)));
  var pos = 0;
  for (final child in (span.children ?? const <InlineSpan>[]).cast<TextSpan>()) {
    pos += child.text!.length;
    if (offset < pos) return child.style!.color;
  }
  return span.style?.color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('apply to a selection: stored and rendered, the rest untouched', () {
    final c = make();
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    c.setColor(red);
    expect(colors(c), [(0, 5, red)]);
    expect(c.activeAttributeValue(AttributeType.color), red);
    expect(rendered(c, 2), const Color(red));
    expect(rendered(c, 8), const Color(0xFF111111));
  });

  test('change, then remove (null) restores the default colour', () {
    final c = make();
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    c.setColor(red);
    c.setColor(blue);
    expect(colors(c), [(0, 5, blue)]);
    c.setColor(null);
    expect(colors(c), isEmpty);
    expect(c.activeAttributeValue(AttributeType.color), isNull);
    expect(rendered(c, 2), const Color(0xFF111111));
  });

  test('a mixed selection reports no single colour; applying one unifies it', () {
    final c = make();
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    c.setColor(red);
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    c.setColor(blue);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 11);
    expect(c.activeAttributeValue(AttributeType.color), isNull, reason: 'two colours: nothing to indicate');
    c.setColor(red);
    expect(c.activeAttributeValue(AttributeType.color), red);
    expect(colors(c).map((e) => e.$3).toSet(), {red});
    // partially coloured selection is also "mixed"
    c.setColor(null);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    c.setColor(blue);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    expect(c.activeAttributeValue(AttributeType.color), isNull);
  });

  test('collapsed caret: the colour applies to what is typed next, and only that', () {
    final c = make('ab');
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 2);
    c.setColor(red);
    c.value = const TextEditingValue(text: 'abXY', selection: TextSelection.collapsed(offset: 4));
    expect(colors(c), [(2, 4, red)]);
    // moving away drops the pending colour
    c.selection = const TextSelection.collapsed(offset: 0);
    c.value = const TextEditingValue(text: 'zabXY', selection: TextSelection.collapsed(offset: 1));
    expect(colors(c).where((e) => e.$1 == 0), isEmpty);
  });

  test('undo/redo steps through apply, change and remove', () {
    final c = make();
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    c.setColor(red);
    c.setColor(blue);
    c.setColor(null);
    c.undo();
    expect(colors(c), [(0, 5, blue)]);
    c.undo();
    expect(colors(c), [(0, 5, red)]);
    c.undo();
    expect(colors(c), isEmpty);
    c.redo();
    c.redo();
    c.redo();
    expect(colors(c), isEmpty);
    c.undo();
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    expect(c.activeAttributeValue(AttributeType.color), blue);
  });

  test('clear formatting removes colour along with the rest', () {
    final c = make();
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    c.setColor(red);
    c.toggleBold();
    c.clearFormatting();
    expect(colors(c), isEmpty);
    expect(c.document.attributes, isEmpty);
    c.undo();
    expect(colors(c), [(0, 5, red)]);
  });

  test('colour survives typing inside a coloured run and splitting it', () {
    final c = make('abcd');
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    c.setColor(red);
    c.value = const TextEditingValue(text: 'abXcd', selection: TextSelection.collapsed(offset: 3));
    expect(colors(c), [(0, 5, red)]);
  });

  test('colour does not change the one-row policy', () {
    final c = make();
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    c.setColor(red);
    c.toggleBold();
    final span = c.renderer.renderSpan(c.document, style: const TextStyle(fontSize: 16));
    final colored = span.children!.cast<TextSpan>().first.style!;
    final plain = span.children!.cast<TextSpan>().last.style!;
    expect(colored.height! * colored.fontSize!, closeTo(plain.height! * plain.fontSize!, 1e-9));
  });

  group('import / export', () {
    test('JSON round trip', () {
      final c = make();
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      c.setColor(blue);
      final back = EditorDocument.fromJson(c.toJson());
      expect(back.attributes.where((a) => a.type == AttributeType.color).map((a) => (a.start, a.end, a.value)), [(6, 11, blue)]);
    });

    test('HTML export writes a colour span; our own marked HTML re-imports it', () {
      final doc = EditorDocument.fromText('hello world', const [
        TextAttribute(start: 6, end: 11, type: AttributeType.color, value: red),
        TextAttribute(start: 6, end: 11, type: AttributeType.bold),
      ]);
      final html = const HtmlExporter(marker: true).export(doc.text, doc.exportAttributes());
      expect(html, contains('<span style="color:#d32f2f">'));
      final back = const HtmlImporter().parse(html);
      expect(back.text, 'hello world');
      expect(back.attributes.where((a) => a.type == AttributeType.color).map((a) => (a.start, a.end, a.value)), [(6, 11, red)]);
      expect(back.attributes.any((a) => a.type == AttributeType.bold), isTrue);
    });

    test('colours from a copied web page are not imported (they would pin a fixed grey in dark mode)', () {
      final r = const HtmlImporter().parse('<div style="color: rgb(33,37,41)"><p style="color:#212529">Hello <span style="color:#ff0000">red</span></p></div>');
      expect(r.text, 'Hello red');
      expect(r.attributes.where((a) => a.type == AttributeType.color), isEmpty);
    });

    test('Markdown has no colour syntax: the text exports intact, without it', () {
      final doc = EditorDocument.fromText('hello', const [TextAttribute(start: 0, end: 5, type: AttributeType.color, value: red)]);
      expect(const MarkdownExporter().export(doc.text, doc.exportAttributes()), 'hello');
    });
  });

  group('copy / paste', () {
    const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');
    String? html;
    String? plain;
    setUp(() {
      html = null;
      plain = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setData') {
          html = (call.arguments as Map)['html'] as String?;
          plain = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'getData') return {'text': plain, 'html': html};
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('within the app (rich clipboard): colour is kept', () async {
      final a = make();
      addTearDown(a.dispose);
      a.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      a.setColor(red);
      await a.copy();
      final b = make('');
      addTearDown(b.dispose);
      await b.paste();
      expect(colors(b), [(0, 5, red)]);
    });

    test('through the system clipboard HTML only (no in-memory delegate): colour is kept too', () async {
      final a = make();
      addTearDown(a.dispose);
      a.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      a.setColor(blue);
      await a.copy();
      InMemoryRichClipboardDelegate.shared.store('something else', const []);
      final b = make('');
      addTearDown(b.dispose);
      await b.paste();
      expect(b.document.text, 'world');
      expect(colors(b), [(0, 5, blue)]);
    });
  });
}
