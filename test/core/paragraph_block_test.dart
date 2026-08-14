import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/core/paragraph_block.dart';
import 'package:lightweight_rich_editor/src/core/paragraph_index.dart';
import 'package:lightweight_rich_editor/src/models/paragraph_alignment.dart';
import 'package:lightweight_rich_editor/src/utils/list_prefix.dart';

void main() {
  group('ParagraphBlock.derive', () {
    test('plain paragraph has no listType, no checked state, no indent', () {
      final index = ParagraphIndex.rebuild('Just text');
      final block = ParagraphBlock.derive(index.records.first, 'Just text');
      expect(block.listType, isNull);
      expect(block.checked, isNull);
      expect(block.indentLevel, 0);
    });

    test('bullet paragraph reports bullet listType and null checked', () {
      const text = '- Item';
      final index = ParagraphIndex.rebuild(text);
      final block = ParagraphBlock.derive(index.records.first, text);
      expect(block.listType, ParagraphListType.bullet);
      expect(block.checked, isNull);
    });

    test('numbered paragraph reports numbered listType and null checked', () {
      const text = '1. Item';
      final index = ParagraphIndex.rebuild(text);
      final block = ParagraphBlock.derive(index.records.first, text);
      expect(block.listType, ParagraphListType.numbered);
      expect(block.checked, isNull);
    });

    test('unchecked task item reports bullet listType and checked: false', () {
      const text = '- [ ] Task';
      final index = ParagraphIndex.rebuild(text);
      final block = ParagraphBlock.derive(index.records.first, text);
      expect(block.listType, ParagraphListType.bullet);
      expect(block.checked, isFalse);
    });

    test('checked task item reports checked: true', () {
      const text = '- [x] Task';
      final index = ParagraphIndex.rebuild(text);
      final block = ParagraphBlock.derive(index.records.first, text);
      expect(block.checked, isTrue);
    });

    test('indent level reflects leading whitespace, independent of list-ness', () {
      const text = '    Indented plain text';
      final index = ParagraphIndex.rebuild(text);
      final block = ParagraphBlock.derive(index.records.first, text);
      expect(block.listType, isNull);
      expect(block.indentLevel, 2); // 4 spaces / 2
    });

    test('nested checked item combines indent, listType, and checked', () {
      const text = '    - [x] Nested done item';
      final index = ParagraphIndex.rebuild(text);
      final block = ParagraphBlock.derive(index.records.first, text);
      expect(block.listType, ParagraphListType.bullet);
      expect(block.checked, isTrue);
      expect(block.indentLevel, 2);
    });

    test('headerLevel and alignment pass through from the record unchanged', () {
      final index = ParagraphIndex.rebuild('Heading');
      index.setHeaderLevel(0, 7, 'h1');
      index.setAlignment(0, 7, ParagraphAlignment.center);
      final block = ParagraphBlock.derive(index.records.first, 'Heading');
      expect(block.headerLevel, 'h1');
      expect(block.alignment, ParagraphAlignment.center);
    });
  });
}
