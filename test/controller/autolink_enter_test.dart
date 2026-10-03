import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  RichEditorController typed(String text) {
    final c = RichEditorController();
    for (final ch in text.split('')) {
      final next = c.document.text + ch;
      c.value = c.value.copyWith(text: next, selection: TextSelection.collapsed(offset: next.length));
    }
    return c;
  }

  List<String> links(RichEditorController c) =>
      c.document.attributes.where((a) => a.type == AttributeType.link).map((a) => c.document.text.substring(a.start, a.end)).toList();

  test('a space after the address links it', () => expect(links(typed('docs.flutter.dev ')), ['docs.flutter.dev']));
  test('Enter after the address links it', () => expect(links(typed('docs.flutter.dev\n')), ['docs.flutter.dev']));
  test('Enter after an e-mail address links it', () => expect(links(typed('me@site.com\n')), ['me@site.com']));
  test('Enter after a full https address links it', () => expect(links(typed('https://a.io/x\n')), ['https://a.io/x']));
}
