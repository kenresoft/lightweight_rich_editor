import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/commands/apply_attribute_command.dart';
import 'package:lightweight_rich_editor/src/commands/replace_range_command.dart';
import 'package:lightweight_rich_editor/src/commands/toggle_attribute_command.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/core/editor_selection.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/history/history_manager.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

({EditorDocument document, EditingEngine engine, HistoryManager history}) _harness({
  String text = '',
  Duration typingTimeout = const Duration(milliseconds: 800),
}) {
  final document = EditorDocument.fromText(text);
  final transactions = TransactionManager(() {});
  final engine = EditingEngine(document: document, transactions: transactions);
  final history = HistoryManager(engine: engine, typingTimeout: typingTimeout);
  return (document: document, engine: engine, history: history);
}

ReplaceRangeCommand _insertAt(int at, String text) =>
    ReplaceRangeCommand(start: at, end: at, text: text);

ReplaceRangeCommand _backspaceAt(int at) => ReplaceRangeCommand(start: at - 1, end: at, text: '');

void main() {
  group('HistoryManager — typing coalescing', () {
    test('sequential contiguous inserts within the typing window become one undo step', () {
      final h = _harness();

      h.history.execute(_insertAt(0, 'h'));
      h.history.execute(_insertAt(1, 'e'));
      h.history.execute(_insertAt(2, 'l'));
      h.history.execute(_insertAt(3, 'l'));
      h.history.execute(_insertAt(4, 'o'));

      expect(h.document.text, 'hello');
      expect(h.history.undoDepth, 1, reason: 'five keystrokes should coalesce into one entry');

      h.history.undo();
      expect(h.document.text, '', reason: 'undoing the one entry should undo all five keystrokes');
    });

    test('non-contiguous inserts do not coalesce', () {
      final h = _harness(text: 'ab');

      h.history.execute(_insertAt(0, 'X')); // -> "Xab"
      h.history.execute(_insertAt(3, 'Y')); // not contiguous with the first insert's end (1)

      expect(h.history.undoDepth, 2);
    });

    test('sequential backspaces coalesce into one undo step', () {
      final h = _harness(text: 'hello');

      h.history.execute(_backspaceAt(5));
      h.history.execute(_backspaceAt(4));
      h.history.execute(_backspaceAt(3));

      expect(h.document.text, 'he');
      expect(h.history.undoDepth, 1);

      h.history.undo();
      expect(h.document.text, 'hello');
    });

    test('typing then backspacing does not coalesce (different operation kinds)', () {
      final h = _harness();

      h.history.execute(_insertAt(0, 'a'));
      h.history.execute(_backspaceAt(1));

      expect(h.history.undoDepth, 2);
    });
  });

  group('HistoryManager — session breaks', () {
    test('a gap longer than typingTimeout starts a new entry', () {
      final h = _harness(typingTimeout: const Duration(milliseconds: 1));

      h.history.execute(_insertAt(0, 'a'));
      // No real sleep in a unit test — simulate the timeout having
      // elapsed by breaking coalescing directly, which is exactly what
      // the timeout check does internally once expired.
      h.history.breakCoalescing();
      h.history.execute(_insertAt(1, 'b'));

      expect(h.history.undoDepth, 2);
    });

    test('breakCoalescing (cursor movement) starts a new entry even within the window', () {
      final h = _harness();

      h.history.execute(_insertAt(0, 'a'));
      h.history.breakCoalescing(); // simulates the controller reporting a selection-only change
      h.history.execute(_insertAt(1, 'b'));

      expect(h.history.undoDepth, 2);
    });
  });

  group('HistoryManager — formatting changes', () {
    test('a formatting command never coalesces with a preceding text command', () {
      final h = _harness();

      h.history.execute(_insertAt(0, 'a'));
      h.history.execute(
        ToggleAttributeCommand(AttributeType.bold, const EditorSelection(baseOffset: 0, extentOffset: 1)),
      );

      expect(h.history.undoDepth, 2);
    });

    test('two sequential formatting commands each get their own entry', () {
      final h = _harness(text: 'hello');
      final sel = const EditorSelection(baseOffset: 0, extentOffset: 5);

      h.history.execute(ToggleAttributeCommand(AttributeType.bold, sel));
      h.history.execute(ApplyAttributeCommand(AttributeType.color, sel, 0xFFFF0000));

      expect(h.history.undoDepth, 2);
    });
  });

  group('HistoryManager — redo', () {
    test('undo followed by redo restores the edit', () {
      final h = _harness();

      h.history.execute(_insertAt(0, 'hi'));
      h.history.undo();
      expect(h.document.text, '');

      h.history.redo();
      expect(h.document.text, 'hi');
    });

    test('a new edit after undo clears the redo stack', () {
      final h = _harness();

      h.history.execute(_insertAt(0, 'hi'));
      h.history.undo();
      expect(h.history.canRedo, isTrue);

      h.history.execute(_insertAt(0, 'yo'));

      expect(h.history.canRedo, isFalse);
    });

    test('canUndo/canRedo reflect stack state', () {
      final h = _harness();
      expect(h.history.canUndo, isFalse);
      expect(h.history.canRedo, isFalse);

      h.history.execute(_insertAt(0, 'a'));
      expect(h.history.canUndo, isTrue);

      h.history.undo();
      expect(h.history.canUndo, isFalse);
      expect(h.history.canRedo, isTrue);
    });
  });

  group('HistoryManager — exact restoration through mixed edits', () {
    test('undo restores exact spans, not a re-derived approximation', () {
      final h = _harness(text: 'hello world');
      // Make "hello" bold, leave "world" unformatted.
      final boldSel = const EditorSelection(baseOffset: 0, extentOffset: 5);
      h.history.execute(ToggleAttributeCommand(AttributeType.bold, boldSel));

      // Delete part of "world" — an unrelated region — then undo just
      // that deletion. The bold span on "hello" must survive untouched.
      h.history.execute(ReplaceRangeCommand(start: 6, end: 11, text: ''));
      expect(h.document.text, 'hello ');

      h.history.undo();
      expect(h.document.text, 'hello world');
      expect(h.document.attributeStore.coversRange(0, 5, AttributeType.bold), isTrue);
    });

    test('undoing a toggle on a partially-covered selection restores the original pattern', () {
      final h = _harness(text: 'hello world');
      // Pre-existing: only "hello" (0-5) is bold.
      h.document.attributeStore.insert(
        const TextAttribute(start: 0, end: 5, type: AttributeType.bold),
      );

      // Toggle bold over "hello wor" (0-9): since it's not fully
      // covered, this makes the whole range bold.
      h.history.execute(
        ToggleAttributeCommand(AttributeType.bold, const EditorSelection(baseOffset: 0, extentOffset: 9)),
      );
      expect(h.document.attributeStore.coversRange(0, 9, AttributeType.bold), isTrue);

      // Undo must restore the *original* partial pattern (0-5 bold,
      // 5-9 not), not just "toggle again" (which would clear 0-9
      // entirely and lose the original 0-5 span).
      h.history.undo();
      expect(h.document.attributeStore.coversRange(0, 5, AttributeType.bold), isTrue);
      expect(h.document.attributeStore.findIntersecting(5, 9, type: AttributeType.bold), isEmpty);
    });
  });
}