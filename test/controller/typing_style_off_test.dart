// Turning a style OFF at a caret that sits in or after text with that style must
// stop it for the next typed text (it used to be inherited by the span growing).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  linkAndCodeTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  RichEditorController typeAll(RichEditorController c, String text) {
    for (var i = 1; i <= text.length; i++) {
      final start = c.document.text.length;
      c.value = TextEditingValue(
        text: c.document.text + text[i - 1],
        selection: TextSelection.collapsed(offset: start + 1),
      );
    }
    return c;
  }

  bool bold(RichEditorController c, int offset) => c.document.attributeStore.findAt(offset, type: AttributeType.bold).isNotEmpty;

  test('bold on, type, bold off, type: only the first part is bold', () {
    final c = RichEditorController(text: '');
    addTearDown(c.dispose);
    c.toggleBold();
    typeAll(c, 'bb');
    expect(c.isAttributeActive(AttributeType.bold), isTrue);

    c.toggleBold();
    expect(c.isAttributeActive(AttributeType.bold), isFalse, reason: 'the button follows the toggle');
    typeAll(c, 'pp');

    expect(c.document.text, 'bbpp');
    expect([for (var i = 0; i < 4; i++) bold(c, i)], [true, true, false, false]);
  });

  test('the same for italic, underline and strikethrough, one after the other', () {
    final c = RichEditorController(text: '');
    addTearDown(c.dispose);
    for (final (toggle, type) in <(void Function(), AttributeType)>[
      (c.toggleItalic, AttributeType.italic),
      (c.toggleUnderline, AttributeType.underline),
      (c.toggleStrikethrough, AttributeType.strikethrough),
    ]) {
      toggle();
      typeAll(c, 'x');
      toggle();
      typeAll(c, '.');
      final last = c.document.text.length - 1;
      expect(c.document.attributeStore.findAt(last, type: type), isEmpty, reason: '$type must be off for the text typed after it');
      expect(c.document.attributeStore.findAt(last - 1, type: type), isNotEmpty);
    }
    // Earlier styles did not pile up onto later text.
    expect(c.document.attributeStore.findAt(c.document.text.length - 1), isEmpty);
  });

  test('turning bold off in the middle of bold text splits it', () {
    final c = RichEditorController(text: '');
    addTearDown(c.dispose);
    c.toggleBold();
    typeAll(c, 'abcd');
    c.selection = const TextSelection.collapsed(offset: 2);
    expect(c.isAttributeActive(AttributeType.bold), isTrue);

    c.toggleBold();
    expect(c.isAttributeActive(AttributeType.bold), isFalse);
    c.value = const TextEditingValue(text: 'abXcd', selection: TextSelection.collapsed(offset: 3));

    expect([for (var i = 0; i < 5; i++) bold(c, i)], [true, true, false, true, true]);
  });

  test('typing right after bold text without touching the button stays bold', () {
    final c = RichEditorController(text: '');
    addTearDown(c.dispose);
    c.toggleBold();
    typeAll(c, 'ab');
    typeAll(c, 'c');
    expect([for (var i = 0; i < 3; i++) bold(c, i)], [true, true, true]);
  });

  test('Enter after bold text with bold off starts a plain line', () {
    final c = RichEditorController(text: '');
    addTearDown(c.dispose);
    c.toggleBold();
    typeAll(c, 'bold');
    c.toggleBold();
    c.insertText('\n');
    typeAll(c, 'plain');
    final last = c.document.text.length - 1;
    expect(bold(c, 0), isTrue);
    expect(bold(c, last), isFalse);
  });

  test('undo and redo of text typed after bold was switched off keep it plain', () {
    final c = RichEditorController(text: '');
    addTearDown(c.dispose);
    c.toggleBold();
    typeAll(c, 'ab');
    c.toggleBold();
    c.insertText('x');
    expect(bold(c, 2), isFalse);

    c.undo();
    c.redo();
    expect(c.document.text, 'abx');
    expect([for (var i = 0; i < 3; i++) bold(c, i)], [true, true, false]);
  });

  test('clearing formatting at a caret stops bold for the next typed text', () {
    final c = RichEditorController(text: '');
    addTearDown(c.dispose);
    c.toggleBold();
    typeAll(c, 'ab');
    c.clearFormatting();
    typeAll(c, 'c');
    expect([for (var i = 0; i < 3; i++) bold(c, i)], [true, true, false]);
  });
}

void linkAndCodeTests() {
  group('a link or inline code does not carry onto the next line', () {
    RichEditorController typed(RichEditorController c, String text) {
      for (final ch in text.split('')) {
        final at = c.document.text.length;
        c.value = TextEditingValue(text: c.document.text + ch, selection: TextSelection.collapsed(offset: at + 1));
      }
      return c;
    }

    test('Enter at the end of a link, then typing: the new text is not linked', () {
      final c = RichEditorController(text: 'site');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      c.setLink('https://example.com');
      c.selection = const TextSelection.collapsed(offset: 4);
      c.insertText('\n');
      typed(c, 'next');
      expect(c.document.text, 'site\nnext');
      expect(c.document.attributeStore.findAt(0, type: AttributeType.link), isNotEmpty);
      expect(c.document.attributeStore.findAt(6, type: AttributeType.link), isEmpty);
    });

    test('a space and a word typed after a link are not part of it, also when typed again after deleting', () {
      final c = RichEditorController(text: 'site');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      c.setLink('https://example.com');
      c.selection = const TextSelection.collapsed(offset: 4);
      typed(c, ' more');
      bool linked(int i) => c.document.attributeStore.findAt(i, type: AttributeType.link).isNotEmpty;
      expect([for (var i = 0; i < 9; i++) linked(i)], [true, true, true, true, false, false, false, false, false]);

      // Delete the word and the space, then type them again.
      c.value = const TextEditingValue(text: 'site', selection: TextSelection.collapsed(offset: 4));
      typed(c, ' more');
      expect(c.document.text, 'site more');
      expect([for (var i = 0; i < 9; i++) linked(i)], [true, true, true, true, false, false, false, false, false]);
    });

    test('typing inside a link keeps it linked', () {
      final c = RichEditorController(text: 'site');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      c.setLink('https://example.com');
      c.value = const TextEditingValue(text: 'siXte', selection: TextSelection.collapsed(offset: 3));
      expect(c.document.attributeStore.findAt(2, type: AttributeType.link), isNotEmpty);
      expect(c.document.attributeStore.findAt(4, type: AttributeType.link), isNotEmpty);
    });

    test('the same through the keyboard path', () {
      final c = RichEditorController(text: 'site');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      c.setLink('https://example.com');
      c.selection = const TextSelection.collapsed(offset: 4);
      c.value = const TextEditingValue(text: 'site\n', selection: TextSelection.collapsed(offset: 5));
      typed(c, 'x');
      expect(c.document.attributeStore.findAt(5, type: AttributeType.link), isEmpty);
    });

    test('inline code does not carry onto the next line either', () {
      final c = RichEditorController(text: '');
      addTearDown(c.dispose);
      c.toggleCode();
      typed(c, 'cd');
      c.insertText('\n');
      typed(c, 'plain');
      expect(c.document.attributeStore.findAt(0, type: AttributeType.code), isNotEmpty);
      expect(c.document.attributeStore.findAt(4, type: AttributeType.code), isEmpty);
    });
  });
}
