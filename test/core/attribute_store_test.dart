import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/core/attribute_store.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

void main() {
  group('AttributeStore.shiftForInsertion', () {
    test('moves a span entirely after the insertion point forward', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 5, end: 10, type: AttributeType.bold),
      ]);

      store.shiftForInsertion(2, 3);

      expect(store.spans.single, const TextAttribute(start: 8, end: 13, type: AttributeType.bold));
    });

    test('grows a span that straddles the insertion point', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 10, type: AttributeType.bold),
      ]);

      store.shiftForInsertion(5, 3);

      expect(store.spans.single, const TextAttribute(start: 0, end: 13, type: AttributeType.bold));
    });

    test('leaves a span entirely before the insertion point untouched', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 5, type: AttributeType.bold),
      ]);

      store.shiftForInsertion(10, 3);

      expect(store.spans.single, const TextAttribute(start: 0, end: 5, type: AttributeType.bold));
    });
  });

  group('AttributeStore.shiftForDeletion', () {
    test('drops a span entirely inside the deleted range', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 4, end: 6, type: AttributeType.bold),
      ]);

      store.shiftForDeletion(0, 10);

      expect(store.spans, isEmpty);
    });

    test('shrinks a span straddling the trailing edge of the deletion', () {
      // Span [5, 15), deleting [0, 10) — 5 chars of the span (5..10) were
      // inside the deletion, so the span should become [0, 5).
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 5, end: 15, type: AttributeType.bold),
      ]);

      store.shiftForDeletion(0, 10);

      expect(store.spans.single, const TextAttribute(start: 0, end: 5, type: AttributeType.bold));
    });

    test('shrinks a span straddling the leading edge of the deletion', () {
      // Span [0, 10), deleting [5, 15) — span keeps its first 5 chars.
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 10, type: AttributeType.bold),
      ]);

      store.shiftForDeletion(5, 15);

      expect(store.spans.single, const TextAttribute(start: 0, end: 5, type: AttributeType.bold));
    });

    test('shifts a span entirely after the deletion left by the deleted length', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 20, end: 30, type: AttributeType.bold),
      ]);

      store.shiftForDeletion(0, 10);

      expect(store.spans.single, const TextAttribute(start: 10, end: 20, type: AttributeType.bold));
    });
  });

  group('AttributeStore.optimize', () {
    test('merges adjacent same-value spans of the same type', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 5, type: AttributeType.bold),
        const TextAttribute(start: 5, end: 10, type: AttributeType.bold),
      ]);

      store.optimize();

      expect(store.spans.single, const TextAttribute(start: 0, end: 10, type: AttributeType.bold));
    });

    test('does not merge same-type spans with different values', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 5, type: AttributeType.color, value: 0xFFFF0000),
        const TextAttribute(start: 5, end: 10, type: AttributeType.color, value: 0xFF00FF00),
      ]);

      store.optimize();

      expect(store.spans, hasLength(2));
    });

    test('does not merge spans of different types', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 5, type: AttributeType.bold),
        const TextAttribute(start: 5, end: 10, type: AttributeType.italic),
      ]);

      store.optimize();

      expect(store.spans, hasLength(2));
    });
  });

  group('AttributeStore.clearRange', () {
    test('trims a span that only partially overlaps the cleared range', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 10, type: AttributeType.bold),
      ]);

      store.clearRange(3, 7);

      final spans = store.spans;
      expect(spans, hasLength(2));
      expect(spans[0], const TextAttribute(start: 0, end: 3, type: AttributeType.bold));
      expect(spans[1], const TextAttribute(start: 7, end: 10, type: AttributeType.bold));
    });

    test('respects the type filter, leaving other types untouched', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 10, type: AttributeType.bold),
        const TextAttribute(start: 0, end: 10, type: AttributeType.italic),
      ]);

      store.clearRange(0, 10, type: AttributeType.bold);

      expect(store.spans, hasLength(1));
      expect(store.spans.single.type, AttributeType.italic);
    });
  });

  group('AttributeStore.coversRange', () {
    test('true when a single span fully covers the range', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 10, type: AttributeType.bold),
      ]);

      expect(store.coversRange(2, 8, AttributeType.bold), isTrue);
    });

    test('false when the range is only partially covered', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 0, end: 5, type: AttributeType.bold),
      ]);

      expect(store.coversRange(0, 10, AttributeType.bold), isFalse);
    });
  });

  group('AttributeStore.clampTo', () {
    test('drops spans that collapse to zero width after clamping', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 8, end: 12, type: AttributeType.bold),
      ]);

      store.clampTo(8); // new text is only 8 chars long

      expect(store.spans, isEmpty);
    });

    test('trims a span that partially exceeds the new length', () {
      final store = AttributeStore.fromSpans([
        const TextAttribute(start: 2, end: 12, type: AttributeType.bold),
      ]);

      store.clampTo(8);

      expect(store.spans.single, const TextAttribute(start: 2, end: 8, type: AttributeType.bold));
    });
  });

  group('AttributeStore.revision', () {
    test('increments on a mutating call', () {
      final store = AttributeStore();
      final before = store.revision;

      store.insert(const TextAttribute(start: 0, end: 5, type: AttributeType.bold));

      expect(store.revision, greaterThan(before));
    });

    test('does not increment on a no-op call', () {
      final store = AttributeStore();
      final before = store.revision;

      store.shiftForInsertion(0, 0); // zero-length insertion: no-op
      store.clearRange(0, 0); // empty range: no-op

      expect(store.revision, before);
    });
  });
}