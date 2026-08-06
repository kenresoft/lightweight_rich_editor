import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/commands/replace_range_command.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

EditingEngine _engine(String text) {
  final document = EditorDocument.fromText(text);
  return EditingEngine(document: document, transactions: TransactionManager(() {}));
}

void main() {
  group('ReplaceRangeCommand — rich paste', () {
    test('applies relativeAttributes at their offset in the document, not offset 0', () {
      final engine = _engine('AAA');
      final command = ReplaceRangeCommand(
        start: 3,
        end: 3,
        text: 'BBBCCC',
        relativeAttributes: const [TextAttribute(start: 3, end: 6, type: AttributeType.bold)], // "CCC" is bold
      );

      command.execute(engine);

      expect(engine.document.text, 'AAABBBCCC');
      expect(engine.document.attributeStore.coversRange(6, 9, AttributeType.bold), isTrue);
      expect(engine.document.attributeStore.findIntersecting(3, 6, type: AttributeType.bold), isEmpty);
    });

    test('undo removes the pasted rich content and its spans cleanly', () {
      final engine = _engine('AAA');
      final command = ReplaceRangeCommand(
        start: 3,
        end: 3,
        text: 'BBB',
        relativeAttributes: const [TextAttribute(start: 0, end: 3, type: AttributeType.bold)],
      );

      command.execute(engine);
      command.undo(engine);

      expect(engine.document.text, 'AAA');
      expect(engine.document.attributeStore.spans, isEmpty);
    });
  });

  group('ReplaceRangeCommand — undo/redo round trip preserves mixed formatting', () {
    test('deleting a region with two different attribute types restores both exactly', () {
      final engine = _engine('hello world');
      engine.document.attributeStore.insert(const TextAttribute(start: 0, end: 5, type: AttributeType.bold));
      engine.document.attributeStore.insert(const TextAttribute(start: 6, end: 11, type: AttributeType.italic));

      final command = ReplaceRangeCommand(start: 4, end: 8, text: '');
      command.execute(engine);
      expect(engine.document.text, 'hellrld');

      command.undo(engine);
      expect(engine.document.text, 'hello world');
      expect(engine.document.attributeStore.coversRange(0, 5, AttributeType.bold), isTrue);
      expect(engine.document.attributeStore.coversRange(6, 11, AttributeType.italic), isTrue);
    });

    test('redo (execute again after undo) reproduces the same result', () {
      final engine = _engine('hello world');
      final command = ReplaceRangeCommand(start: 0, end: 5, text: 'howdy');

      command.execute(engine);
      expect(engine.document.text, 'howdy world');

      command.undo(engine);
      expect(engine.document.text, 'hello world');

      command.execute(engine); // redo
      expect(engine.document.text, 'howdy world');
    });
  });

  group('ReplaceRangeCommand — canCoalesceWith', () {
    test('pure inserts coalesce only when contiguous and same insertion attributes', () {
      final a = ReplaceRangeCommand(start: 0, end: 0, text: 'a', attributesForInsertion: {AttributeType.bold: null});
      final contiguousSameAttrs =
      ReplaceRangeCommand(start: 1, end: 1, text: 'b', attributesForInsertion: {AttributeType.bold: null});
      final contiguousDifferentAttrs = ReplaceRangeCommand(start: 1, end: 1, text: 'b');
      final nonContiguous = ReplaceRangeCommand(start: 5, end: 5, text: 'b', attributesForInsertion: {AttributeType.bold: null});

      expect(contiguousSameAttrs.canCoalesceWith(a), isTrue);
      expect(contiguousDifferentAttrs.canCoalesceWith(a), isFalse);
      expect(nonContiguous.canCoalesceWith(a), isFalse);
    });

    test('a rich-paste command never coalesces with anything', () {
      final plainInsert = ReplaceRangeCommand(start: 0, end: 0, text: 'a');
      final richPaste = ReplaceRangeCommand(
        start: 1,
        end: 1,
        text: 'b',
        relativeAttributes: const [],
      );

      expect(richPaste.canCoalesceWith(plainInsert), isFalse);
    });

    test('insert and delete commands never coalesce with each other', () {
      final insert = ReplaceRangeCommand(start: 0, end: 0, text: 'a');
      final delete = ReplaceRangeCommand(start: 0, end: 1, text: '');

      expect(delete.canCoalesceWith(insert), isFalse);
    });
  });
}