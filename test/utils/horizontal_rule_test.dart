import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/utils/horizontal_rule.dart';

void main() {
  group('isHorizontalRuleLine', () {
    test('matches exactly three hyphens', () {
      expect(isHorizontalRuleLine('---', 0, 3), isTrue);
    });

    test('matches a longer run of hyphens', () {
      const text = '----------';
      expect(isHorizontalRuleLine(text, 0, text.length), isTrue);
    });

    test('does not match two hyphens', () {
      expect(isHorizontalRuleLine('--', 0, 2), isFalse);
    });

    test('does not match a bullet prefix', () {
      expect(isHorizontalRuleLine('- Item', 0, 6), isFalse);
    });

    test('does not match hyphens followed by other text', () {
      expect(isHorizontalRuleLine('---abc', 0, 6), isFalse);
    });

    test('does not match hyphens with a leading space', () {
      expect(isHorizontalRuleLine(' ---', 0, 4), isFalse);
    });

    test('does not match an empty range', () {
      expect(isHorizontalRuleLine('', 0, 0), isFalse);
    });

    test('checks only the given range, not the whole string', () {
      const text = 'before\n---\nafter';
      expect(isHorizontalRuleLine(text, 7, 10), isTrue);
    });
  });
}
