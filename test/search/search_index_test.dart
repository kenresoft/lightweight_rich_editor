import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/commands/command_dispatcher.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/history/history_manager.dart';
import 'package:lightweight_rich_editor/src/search/search_index.dart';

({EditorDocument document, SearchIndex search, HistoryManager history}) _harness(String text) {
  final document = EditorDocument.fromText(text);
  final engine = EditingEngine(document: document, transactions: TransactionManager(() {}));
  final history = HistoryManager(engine: engine);
  final commands = CommandDispatcher(engine: engine, history: history);
  return (document: document, search: SearchIndex(document: document, commands: commands), history: history);
}

void main() {
  group('SearchIndex.search — matching', () {
    test('finds all non-overlapping occurrences', () {
      final h = _harness('the cat sat on the mat');
      h.search.search('at');
      expect(h.search.matchCount, 3); // c-AT, s-AT, m-AT
    });

    test('is case-insensitive by default', () {
      final h = _harness('Cat cat CAT');
      h.search.search('cat');
      expect(h.search.matchCount, 3);
    });

    test('caseSensitive: true only matches exact case', () {
      final h = _harness('Cat cat CAT');
      h.search.search('cat', caseSensitive: true);
      expect(h.search.matchCount, 1);
      expect(h.search.currentMatch!.start, 4);
    });

    test('wholeWord: true excludes partial-word matches', () {
      final h = _harness('cat catalog scatter cat');
      h.search.search('cat', wholeWord: true);
      expect(h.search.matchCount, 2); // "cat" at 0 and the final "cat", not catalog/scatter
    });

    test('wholeWord: false (default) matches inside other words too', () {
      final h = _harness('cat catalog scatter cat');
      h.search.search('cat');
      expect(h.search.matchCount, 4);
    });

    test('an empty query clears any previous search', () {
      final h = _harness('cat cat cat');
      h.search.search('cat');
      expect(h.search.matchCount, 3);

      h.search.search('');
      expect(h.search.matchCount, 0);
      expect(h.search.currentIndex, -1);
    });

    test('no matches leaves currentMatch null', () {
      final h = _harness('hello world');
      h.search.search('xyz');
      expect(h.search.matchCount, 0);
      expect(h.search.currentMatch, isNull);
    });

    test('selects the first match automatically', () {
      final h = _harness('a b a b a');
      h.search.search('a');
      expect(h.search.currentIndex, 0);
      expect(h.search.currentMatch!.start, 0);
    });
  });

  group('SearchIndex — navigation', () {
    test('next() advances and wraps around to the first match', () {
      final h = _harness('a-a-a');
      h.search.search('a');
      expect(h.search.matchCount, 3);

      expect(h.search.next()!.start, 2);
      expect(h.search.next()!.start, 4);
      expect(h.search.next()!.start, 0); // wrapped
    });

    test('previous() retreats and wraps around to the last match', () {
      final h = _harness('a-a-a');
      h.search.search('a');

      expect(h.search.previous()!.start, 4); // wrapped backward from index 0
      expect(h.search.previous()!.start, 2);
    });

    test('next()/previous() return null with no matches', () {
      final h = _harness('hello');
      h.search.search('xyz');
      expect(h.search.next(), isNull);
      expect(h.search.previous(), isNull);
    });
  });

  group('SearchIndex.replaceCurrent', () {
    test('replaces the current match and updates the document', () {
      final h = _harness('the cat sat');
      h.search.search('cat');

      h.search.replaceCurrent('dog');

      expect(h.document.text, 'the dog sat');
    });

    test('is undoable as a normal edit', () {
      final h = _harness('the cat sat');
      h.search.search('cat');
      h.search.replaceCurrent('dog');

      h.history.undo();

      expect(h.document.text, 'the cat sat');
    });

    test('refreshes matches after replacing (offsets may have shifted)', () {
      final h = _harness('cat cat cat');
      h.search.search('cat');
      expect(h.search.matchCount, 3);

      h.search.replaceCurrent('kitten'); // longer replacement shifts later offsets

      expect(h.document.text, 'kitten cat cat');
      expect(h.search.matchCount, 2); // re-searched "cat" against the new text
    });

    test('returns null when there is no current match', () {
      final h = _harness('hello');
      h.search.search('xyz');
      expect(h.search.replaceCurrent('anything'), isNull);
    });
  });

  group('SearchIndex.replaceAll', () {
    test('replaces every match and returns the count', () {
      final h = _harness('cat cat cat');
      h.search.search('cat');

      final count = h.search.replaceAll('dog');

      expect(count, 3);
      expect(h.document.text, 'dog dog dog');
    });

    test('handles a replacement of different length without corrupting later matches', () {
      final h = _harness('a cat, a cat, a cat');
      h.search.search('cat');

      h.search.replaceAll('kitten');

      expect(h.document.text, 'a kitten, a kitten, a kitten');
    });

    test('undoes as a single step, not one per match', () {
      final h = _harness('cat cat cat');
      h.search.search('cat');
      h.search.replaceAll('dog');
      expect(h.document.text, 'dog dog dog');

      h.history.undo();

      expect(h.document.text, 'cat cat cat');
      expect(h.history.canUndo, isFalse);
    });

    test('clears the search afterward', () {
      final h = _harness('cat cat');
      h.search.search('cat');
      h.search.replaceAll('dog');

      expect(h.search.matchCount, 0);
      expect(h.search.query, isEmpty);
    });

    test('returns 0 and does nothing with no matches', () {
      final h = _harness('hello');
      h.search.search('xyz');
      expect(h.search.replaceAll('anything'), 0);
      expect(h.document.text, 'hello');
    });
  });

  group('SearchIndex.refresh', () {
    test('re-runs the last query against current text', () {
      final h = _harness('cat');
      h.search.search('cat');
      expect(h.search.matchCount, 1);

      h.document.reset('cat cat');
      h.search.refresh();

      expect(h.search.matchCount, 2);
    });

    test('is a no-op when nothing has been searched', () {
      final h = _harness('hello');
      expect(() => h.search.refresh(), returnsNormally);
      expect(h.search.matchCount, 0);
    });
  });
}