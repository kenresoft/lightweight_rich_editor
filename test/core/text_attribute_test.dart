import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

void main() {
  group('TextAttribute equality', () {
    test('two separately-constructed spans with the same fields are equal', () {
      const a = TextAttribute(start: 0, end: 5, type: AttributeType.bold);
      const b = TextAttribute(start: 0, end: 5, type: AttributeType.bold);

      // This is the property the original controller's undo diffing
      // silently lacked (it compared by identity, not value) — see the
      // Phase 1 analysis. If this regresses, HistoryManager's coalescing
      // and command snapshot/restore logic both silently break.
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a copy via .copy() equals the original when unchanged', () {
      const original = TextAttribute(start: 0, end: 5, type: AttributeType.color, value: 0xFF0000FF);
      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('differs when any field differs', () {
      const base = TextAttribute(start: 0, end: 5, type: AttributeType.bold);

      expect(base, isNot(equals(base.copyWith(start: 1))));
      expect(base, isNot(equals(base.copyWith(end: 6))));
      expect(base, isNot(equals(base.copyWith(type: AttributeType.italic))));
      expect(
        const TextAttribute(start: 0, end: 5, type: AttributeType.color, value: 1),
        isNot(equals(const TextAttribute(start: 0, end: 5, type: AttributeType.color, value: 2))),
      );
    });
  });

  group('TextAttribute serialization', () {
    test('round-trips through toJson/fromJson', () {
      const original = TextAttribute(start: 3, end: 9, type: AttributeType.link, value: 'https://x.test');

      final restored = TextAttribute.fromJson(original.toJson());

      expect(restored, equals(original));
    });

    test('omits the value key entirely for toggle attributes', () {
      const attr = TextAttribute(start: 0, end: 5, type: AttributeType.bold);
      expect(attr.toJson().containsKey('value'), isFalse);
    });
  });
}