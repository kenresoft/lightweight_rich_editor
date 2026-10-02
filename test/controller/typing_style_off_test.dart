// Turning a style OFF at a caret that sits in or after text with that style must
// stop it for the next typed text (it used to be inherited by the span growing).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
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
