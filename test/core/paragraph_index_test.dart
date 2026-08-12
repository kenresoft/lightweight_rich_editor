import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/core/paragraph_index.dart';
import 'package:lightweight_rich_editor/src/core/paragraph_record.dart';

void main() {
  group('ParagraphIndex.rebuild', () {
    test('empty text produces one empty record', () {
      final index = ParagraphIndex.rebuild('');
      expect(index.records, [const ParagraphRecord(start: 0, end: 0)]);
    });

    test('single paragraph, no newline', () {
      final index = ParagraphIndex.rebuild('Hello');
      expect(index.records, [const ParagraphRecord(start: 0, end: 5)]);
    });

    test('three paragraphs', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB\nCCC');
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 3),
        const ParagraphRecord(start: 4, end: 7),
        const ParagraphRecord(start: 8, end: 11),
      ]);
      expect(index.debugValidate('AAA\nBBB\nCCC'.length), isTrue);
    });

    test('trailing newline produces a trailing empty paragraph', () {
      final index = ParagraphIndex.rebuild('AAA\n');
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 3),
        const ParagraphRecord(start: 4, end: 4),
      ]);
    });
  });

  group('ParagraphIndex.paragraphAt', () {
    test('finds the correct record, including exact boundary offsets', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB');
      // record0 = {0,3}, record1 = {4,7}
      expect(index.paragraphAt(0), const ParagraphRecord(start: 0, end: 3));
      expect(index.paragraphAt(3), const ParagraphRecord(start: 0, end: 3)); // the '\n' itself belongs to record0
      expect(index.paragraphAt(4), const ParagraphRecord(start: 4, end: 7)); // right after '\n' belongs to record1
      expect(index.paragraphAt(7), const ParagraphRecord(start: 4, end: 7));
      expect(index.paragraphAt(8), isNull); // out of bounds
    });
  });

  group('ParagraphIndex.applyInsertion — no newline', () {
    test('extends the absorbing record and shifts later ones', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB');
      index.applyInsertion(1, 'XY'); // "AXYAA\nBBB"
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 5), // "AXYAA"
        const ParagraphRecord(start: 6, end: 9), // "BBB", shifted by 2
      ]);
      expect(index.debugValidate(9), isTrue);
    });

    test('insertion exactly at a record end absorbs into that record, not the next', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB');
      index.applyInsertion(3, 'X'); // right at record0's own '\n' position -> "AAAX\nBBB"
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 4), // "AAAX"
        const ParagraphRecord(start: 5, end: 8), // "BBB", shifted by 1
      ]);
    });

    test('insertion exactly at the next record start absorbs into that record instead', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB');
      index.applyInsertion(4, 'X'); // right at record1's own start -> "AAA\nXBBB"
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 3), // untouched
        const ParagraphRecord(start: 4, end: 8), // "XBBB"
      ]);
    });
  });

  group('ParagraphIndex.applyInsertion — with newlines (split)', () {
    test('single newline splits into two, second fragment loses headerLevel', () {
      final index = ParagraphIndex.rebuild('My Header');
      index.setHeaderLevel(0, 9, 'h1');
      index.applyInsertion(4, 'X\nY'); // "My H" + "X\nY" + "eader" = "My HX\nYeader"
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 5, headerLevel: 'h1'), // "My HX" — keeps header
        const ParagraphRecord(start: 6, end: 12), // "Yeader" — does not
      ]);
      expect(index.debugValidate('My HX\nYeader'.length), isTrue);
    });

    test('multiple newlines split into N fragments, only the first keeps headerLevel', () {
      final index = ParagraphIndex.rebuild('My Header');
      index.setHeaderLevel(0, 9, 'h1');
      // "My H" + "X\nY\nZ" + "eader" = "My HX\nY\nZeader"
      index.applyInsertion(4, 'X\nY\nZ');
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 5, headerLevel: 'h1'), // "My HX"
        const ParagraphRecord(start: 6, end: 7), // "Y"
        const ParagraphRecord(start: 8, end: 14), // "Zeader"
      ]);
      expect(index.debugValidate('My HX\nY\nZeader'.length), isTrue);
    });
  });

  group('ParagraphIndex.applyDeletion — no paragraph break crossed', () {
    test('shrinks a single record, headerLevel untouched', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB');
      index.applyDeletion(5, 6); // remove middle char of "BBB" -> "AAA\nBB"
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 3),
        const ParagraphRecord(start: 4, end: 6),
      ]);
      expect(index.debugValidate('AAA\nBB'.length), isTrue);
    });
  });

  group('ParagraphIndex.applyDeletion — crossing paragraph breaks (merge)', () {
    test('deleting a whole middle paragraph plus both separators merges three into one', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB\nCCC');
      index.setHeaderLevel(0, 3, 'h1'); // leftmost record is the header
      index.applyDeletion(3, 8); // removes '\n', "BBB", '\n' -> "AAA" + "CCC" = "AAACCC"
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 6, headerLevel: 'h1'), // merged keeps leftmost's headerLevel
      ]);
      expect(index.debugValidate('AAACCC'.length), isTrue);
    });

    test('deletion spanning partial-first + full-middle + partial-last', () {
      final index = ParagraphIndex.rebuild('AAAA\nBBBB\nCCCC');
      index.setHeaderLevel(0, 4, 'h2');
      index.applyDeletion(2, 12); // -> "AA" + "CC" = "AACC"
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 4, headerLevel: 'h2'),
      ]);
      expect(index.debugValidate('AACC'.length), isTrue);
    });

    test('deletion crossing breaks with no headerLevel anywhere collapses cleanly', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB\nCCC');
      index.applyDeletion(3, 8);
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 6),
      ]);
    });
  });

  group('ParagraphIndex.setHeaderLevel', () {
    test('sets on a single paragraph', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB');
      index.setHeaderLevel(0, 3, 'h1');
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 3, headerLevel: 'h1'),
        const ParagraphRecord(start: 4, end: 7),
      ]);
    });

    test('a range spanning multiple paragraphs sets all of them, matching the '
        'existing multi-paragraph AttributeStore span behavior', () {
      final index = ParagraphIndex.rebuild('AAA\nBBB\nCCC');
      index.setHeaderLevel(0, 11, 'h2');
      expect(index.records, [
        const ParagraphRecord(start: 0, end: 3, headerLevel: 'h2'),
        const ParagraphRecord(start: 4, end: 7, headerLevel: 'h2'),
        const ParagraphRecord(start: 8, end: 11, headerLevel: 'h2'),
      ]);
    });

    test('null clears headerLevel', () {
      final index = ParagraphIndex.rebuild('AAA');
      index.setHeaderLevel(0, 3, 'h1');
      index.setHeaderLevel(0, 3, null);
      expect(index.records, [const ParagraphRecord(start: 0, end: 3)]);
    });
  });
}