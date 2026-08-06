import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';

void main() {
  group('TransactionManager', () {
    test('notify() outside a transaction fires onCommit immediately, once per call', () {
      var commits = 0;
      final tx = TransactionManager(() => commits++);

      tx.notify();
      tx.notify();

      expect(commits, 2);
    });

    test('multiple notify() calls inside run() coalesce into one onCommit', () {
      var commits = 0;
      final tx = TransactionManager(() => commits++);

      tx.run(() {
        tx.notify();
        tx.notify();
        tx.notify();
      });

      expect(commits, 1);
    });

    test('run() with no notify() calls inside does not fire onCommit', () {
      var commits = 0;
      final tx = TransactionManager(() => commits++);

      tx.run(() {});

      expect(commits, 0);
    });

    test('nested run() calls only commit once, at the outermost exit', () {
      var commits = 0;
      final tx = TransactionManager(() => commits++);

      tx.run(() {
        tx.notify();
        tx.run(() {
          tx.notify();
        });
        tx.notify();
      });

      expect(commits, 1);
    });

    test('isInTransaction reflects nesting depth', () {
      final tx = TransactionManager(() {});
      expect(tx.isInTransaction, isFalse);

      tx.run(() {
        expect(tx.isInTransaction, isTrue);
        tx.run(() {
          expect(tx.isInTransaction, isTrue);
        });
        expect(tx.isInTransaction, isTrue);
      });

      expect(tx.isInTransaction, isFalse);
    });

    test("run() returns the action's return value", () {
      final tx = TransactionManager(() {});
      final result = tx.run(() => 42);
      expect(result, 42);
    });

    test('a transaction still commits once even if the action throws', () {
      var commits = 0;
      final tx = TransactionManager(() => commits++);

      expect(() {
        tx.run(() {
          tx.notify();
          throw StateError('boom');
        });
      }, throwsStateError);

      expect(commits, 1);
    });
  });
}