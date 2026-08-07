import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/core/editor_selection.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

EditingEngine _engine(String text, {List<TextAttribute> attributes = const []}) {
  final document = EditorDocument.fromText(text, attributes);
  final transactions = TransactionManager(() {});
  return EditingEngine(document: document, transactions: transactions);
}

void main() {
  group('EditingEngine.insert / replaceRange', () {
    test('inserting at a collapsed selection just inserts', () {
      final engine = _engine('hello world');

      engine.insert(const EditorSelection.collapsed(5), ',');

      expect(engine.document.text, 'hello, world');
    });

    test('inserting over a non-collapsed selection replaces it', () {
      final engine = _engine('hello world');

      engine.insert(const EditorSelection(baseOffset: 0, extentOffset: 5), 'goodbye');

      expect(engine.document.text, 'goodbye world');
    });

    test('inserted text picks up pending sticky attributes', () {
      final engine = _engine('ab');
      engine.toggleAttribute(AttributeType.bold, const EditorSelection.collapsed(1));

      engine.insert(const EditorSelection.collapsed(1), 'X');

      expect(engine.document.text, 'aXb');
      final spans = engine.document.attributeStore.findAt(1, type: AttributeType.bold);
      expect(spans, hasLength(1));
    });

    test('a span straddling the insertion point absorbs it (typing stays bold)', () {
      final engine = _engine(
        'abcdef',
        attributes: const [TextAttribute(start: 0, end: 6, type: AttributeType.bold)],
      );

      engine.insert(const EditorSelection.collapsed(3), 'X');

      expect(engine.document.text, 'abcXdef');
      expect(engine.document.attributeStore.coversRange(0, 7, AttributeType.bold), isTrue);
    });
  });

  group('EditingEngine.deleteBackward / deleteForward', () {
    test('deleteBackward removes the character before the caret', () {
      final engine = _engine('hello');

      final result = engine.deleteBackward(const EditorSelection.collapsed(5));

      expect(engine.document.text, 'hell');
      expect(result, const EditorSelection.collapsed(4));
    });

    test('deleteBackward at offset 0 is a no-op', () {
      final engine = _engine('hello');

      final result = engine.deleteBackward(const EditorSelection.collapsed(0));

      expect(engine.document.text, 'hello');
      expect(result, const EditorSelection.collapsed(0));
    });

    test('deleteForward removes the character after the caret', () {
      final engine = _engine('hello');

      engine.deleteForward(const EditorSelection.collapsed(0));

      expect(engine.document.text, 'ello');
    });

    test('deleteBackward/deleteForward on a non-collapsed selection deletes the whole selection', () {
      final engine = _engine('hello world');

      engine.deleteBackward(const EditorSelection(baseOffset: 0, extentOffset: 5));

      expect(engine.document.text, ' world');
    });
  });

  group('EditingEngine.toggleAttribute', () {
    test('applies to an unformatted selection', () {
      final engine = _engine('hello world');

      engine.toggleAttribute(AttributeType.bold, const EditorSelection(baseOffset: 0, extentOffset: 5));

      expect(engine.document.attributeStore.coversRange(0, 5, AttributeType.bold), isTrue);
    });

    test('removes from a fully-covered selection', () {
      final engine = _engine(
        'hello world',
        attributes: const [TextAttribute(start: 0, end: 5, type: AttributeType.bold)],
      );

      engine.toggleAttribute(AttributeType.bold, const EditorSelection(baseOffset: 0, extentOffset: 5));

      expect(engine.document.attributeStore.findIntersecting(0, 5, type: AttributeType.bold), isEmpty);
    });

    test('a partially-bold selection becomes fully bold, not fully un-bold', () {
      final engine = _engine(
        'hello world',
        attributes: const [TextAttribute(start: 0, end: 3, type: AttributeType.bold)],
      );

      engine.toggleAttribute(AttributeType.bold, const EditorSelection(baseOffset: 0, extentOffset: 5));

      expect(engine.document.attributeStore.coversRange(0, 5, AttributeType.bold), isTrue);
    });

    test('on a collapsed selection, toggles sticky state instead of touching spans', () {
      final engine = _engine('hello');

      engine.toggleAttribute(AttributeType.bold, const EditorSelection.collapsed(2));

      expect(engine.stickyAttributes.containsKey(AttributeType.bold), isTrue);
      expect(engine.document.attributeStore.spans, isEmpty);
    });
  });

  group('EditingEngine.applyAttribute — header (paragraph-scoped)', () {
    test('applies to the whole line even with a collapsed caret mid-line', () {
      final engine = _engine('first line\nsecond line\nthird line');
      final secondLineStart = 'first line\n'.length;
      final caretInSecondLine = secondLineStart + 3;

      engine.applyAttribute(AttributeType.header, EditorSelection.collapsed(caretInSecondLine), 'h1');

      final expectedStart = secondLineStart;
      final expectedEnd = secondLineStart + 'second line'.length;
      final spans = engine.document.attributeStore.findIntersecting(
        expectedStart,
        expectedEnd,
        type: AttributeType.header,
      );
      expect(spans, hasLength(1));
      expect(spans.single.start, expectedStart);
      expect(spans.single.end, expectedEnd);
    });

    test('does not bleed into neighboring lines', () {
      final engine = _engine('aaa\nbbb\nccc');

      engine.applyAttribute(AttributeType.header, const EditorSelection.collapsed(5), 'h1'); // in "bbb"

      final store = engine.document.attributeStore;
      expect(store.findAt(1, type: AttributeType.header), isEmpty); // in "aaa"
      expect(store.findAt(9, type: AttributeType.header), isEmpty); // in "ccc"
    });

    test('does not bleed onto a new paragraph created by pressing Enter and typing', () {
      // Regression test: AttributeStore.shiftForInsertion's "a span
      // straddling the insertion point absorbs it" rule is correct for
      // character-level formatting (typing mid-bold-text stays bold) but
      // was, before this fix, also letting a header span absorb a
      // newline typed at its end — after which every further typed
      // character landed exactly at the span's new end and grew it
      // again, bleeding the header onto the new paragraph indefinitely.
      final engine = _engine('Title');
      engine.applyAttribute(AttributeType.header, const EditorSelection.collapsed(2), 'h1');
      expect(engine.document.attributeStore.coversRange(0, 5, AttributeType.header), isTrue);

      engine.insert(const EditorSelection.collapsed(5), '\n');
      engine.insert(const EditorSelection.collapsed(6), 'Body text');

      expect(engine.document.text, 'Title\nBody text');
      // The original "Title" paragraph is still a header...
      expect(engine.document.attributeStore.coversRange(0, 5, AttributeType.header), isTrue);
      // ...but none of the new paragraph is.
      expect(engine.document.attributeStore.findIntersecting(6, 15, type: AttributeType.header), isEmpty);
    });
  });

  group('EditingEngine.clearFormatting', () {
    test('removes every attribute type from the selection', () {
      final engine = _engine(
        'hello',
        attributes: const [
          TextAttribute(start: 0, end: 5, type: AttributeType.bold),
          TextAttribute(start: 0, end: 5, type: AttributeType.italic),
        ],
      );

      engine.clearFormatting(const EditorSelection(baseOffset: 0, extentOffset: 5));

      expect(engine.document.attributeStore.spans, isEmpty);
    });

    test('on a collapsed selection, clears pending sticky attributes', () {
      final engine = _engine('hello');
      engine.toggleAttribute(AttributeType.bold, const EditorSelection.collapsed(0));
      expect(engine.stickyAttributes, isNotEmpty);

      engine.clearFormatting(const EditorSelection.collapsed(0));

      expect(engine.stickyAttributes, isEmpty);
    });
  });

  group('EditingEngine.restoreRange', () {
    test('re-inserts text with the exact attributes given, ignoring sticky state', () {
      final engine = _engine('ac');
      engine.toggleAttribute(AttributeType.italic, const EditorSelection.collapsed(1)); // sticky italic pending

      engine.restoreRange(1, 'b', const [TextAttribute(start: 1, end: 2, type: AttributeType.bold)]);

      expect(engine.document.text, 'abc');
      expect(engine.document.attributeStore.findAt(1, type: AttributeType.bold), hasLength(1));
      expect(engine.document.attributeStore.findAt(1, type: AttributeType.italic), isEmpty);
    });
  });
}