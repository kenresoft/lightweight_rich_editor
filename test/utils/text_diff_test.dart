import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/utils/text_diff.dart';

void main() {
  group('diffText — unambiguous cases', () {
    test('detects a pure insertion in the middle', () {
      final diff = diffText('hello world', 'hello, world');

      expect(diff.start, 5);
      expect(diff.end, 5);
      expect(diff.insertedText, ',');
    });

    test('detects a pure deletion', () {
      final diff = diffText('hello world', 'hello');

      expect(diff.start, 5);
      expect(diff.end, 11);
      expect(diff.insertedText, isEmpty);
    });

    test('detects a replace in the middle', () {
      final diff = diffText('hello world', 'hello there');

      expect(diff.start, 6);
      expect(diff.end, 11);
      expect(diff.insertedText, 'there');
    });

    test('no-op for identical strings', () {
      final diff = diffText('same', 'same');
      expect(diff.isNoOp, isTrue);
    });

    test('detects insertion at the very start', () {
      final diff = diffText('world', 'hello world');
      expect(diff.start, 0);
      expect(diff.end, 0);
      expect(diff.insertedText, 'hello ');
    });

    test('detects insertion at the very end', () {
      final diff = diffText('hello', 'hello world');
      expect(diff.start, 5);
      expect(diff.end, 5);
      expect(diff.insertedText, ' world');
    });
  });

  group('diffText — ambiguous cases resolved by cursorHint', () {
    // "a" -> "aa": could be "inserted 'a' before the original" or
    // "inserted 'a' after it" — both produce the same result. The
    // cursor's position before the edit disambiguates.
    test('cursor at the end resolves to an append', () {
      final diff = diffText('a', 'aa', cursorHint: 1);
      expect(diff.start, 1);
      expect(diff.end, 1);
      expect(diff.insertedText, 'a');
    });

    test('cursor at the start resolves to a prepend', () {
      final diff = diffText('a', 'aa', cursorHint: 0);
      expect(diff.start, 0);
      expect(diff.end, 0);
      expect(diff.insertedText, 'a');
    });

    test('no cursorHint falls back to preferring the longest prefix match', () {
      final diff = diffText('a', 'aa');
      // Longest prefix match: prefixMax = 1, so the insertion is placed
      // after the existing character.
      expect(diff.start, 1);
      expect(diff.insertedText, 'a');
    });

    test('repeated-character deletion is resolved the same way', () {
      // "aa" -> "a": ambiguous whether the first or second 'a' was
      // deleted; a cursorHint of 0 should delete from the front.
      final diff = diffText('aa', 'a', cursorHint: 0);
      expect(diff.start, 0);
      expect(diff.end, 1);
    });
  });

  group('diffText — round-trip sanity', () {
    test('applying the diff to oldText reproduces newText', () {
      const oldText = 'The quick brown fox';
      const newText = 'The quick red fox jumps';

      final diff = diffText(oldText, newText, cursorHint: 14);
      final reconstructed = oldText.replaceRange(diff.start, diff.end, diff.insertedText);

      expect(reconstructed, newText);
    });
  });
}