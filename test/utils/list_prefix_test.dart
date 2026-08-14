import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/utils/list_prefix.dart';

void main() {
  group('listPrefixLength — checkbox syntax', () {
    test('matches a plain bullet without a checkbox, as before', () {
      expect(listPrefixLength('- Item', 0), '- '.length);
    });

    test('matches a bullet with an unchecked checkbox', () {
      expect(listPrefixLength('- [ ] Task', 0), '- [ ] '.length);
    });

    test('matches a bullet with a checked checkbox (lowercase x)', () {
      expect(listPrefixLength('- [x] Task', 0), '- [x] '.length);
    });

    test('matches a bullet with a checked checkbox (uppercase X)', () {
      expect(listPrefixLength('- [X] Task', 0), '- [X] '.length);
    });

    test('does not match a checkbox segment after a numbered marker', () {
      // The checkbox syntax is only recognized after a bullet; a numbered
      // item followed by literal "[ ] " just isn't part of the prefix.
      expect(listPrefixLength('1. [ ] Task', 0), '1. '.length);
    });

    test('indentation before a checkbox bullet is still recognized', () {
      expect(listPrefixLength('  - [x] Nested', 0), '  - [x] '.length);
    });
  });

  group('checkboxStateOfPrefix', () {
    test('null for a plain bullet with no checkbox', () {
      expect(checkboxStateOfPrefix('- '), isNull);
    });

    test('null for a numbered prefix', () {
      expect(checkboxStateOfPrefix('1. '), isNull);
    });

    test('false for an unchecked checkbox', () {
      expect(checkboxStateOfPrefix('- [ ] '), isFalse);
    });

    test('true for a checked checkbox, either case', () {
      expect(checkboxStateOfPrefix('- [x] '), isTrue);
      expect(checkboxStateOfPrefix('- [X] '), isTrue);
    });
  });

  group('nextListPrefix — checkbox continuation', () {
    test('an unchecked item continues unchecked', () {
      expect(nextListPrefix('- [ ] '), '- [ ] ');
    });

    test('a checked item continues unchecked, not carrying checked state forward', () {
      expect(nextListPrefix('- [x] '), '- [ ] ');
      expect(nextListPrefix('  - [X] '), '  - [ ] ');
    });

    test('a plain bullet is unaffected', () {
      expect(nextListPrefix('- '), '- ');
    });

    test('a numbered marker still increments as before', () {
      expect(nextListPrefix('3. '), '4. ');
    });
  });

  group('listIndentWhitespace', () {
    test('empty string for a flush-left paragraph', () {
      expect(listIndentWhitespace('- Item', 0), '');
    });

    test('returns exactly the leading spaces, regardless of list-ness', () {
      expect(listIndentWhitespace('    Plain indented text', 0), '    ');
      expect(listIndentWhitespace('  - Nested item', 0), '  ');
    });

    test('resolves relative to paragraphStart, not the start of the string', () {
      const text = 'First\n    Second';
      final secondStart = text.indexOf('Second') - 4;
      expect(listIndentWhitespace(text, secondStart), '    ');
    });
  });
}
