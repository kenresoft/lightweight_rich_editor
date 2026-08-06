import '../commands/composite_command.dart';
import '../commands/editor_command.dart';
import '../core/editing_engine.dart';
import '../core/editor_selection.dart';

/// Owns undo/redo for an [EditingEngine] and decides how edits group into
/// history entries.
///
/// Behavior target (from the product brief): sequential typing becomes
/// one history event, sequential deletes become one history event,
/// formatting changes always get their own, and cursor movement starts a
/// new typing session — matching VS Code / Notion / Obsidian / Apple
/// Notes rather than recording one entry per keystroke like the old
/// controller did.
///
/// [HistoryManager] never mutates the document itself; every stack entry
/// is an [EditorCommand], and it's the command's job to know how to
/// apply and reverse itself. This class only decides *when* two commands
/// belong in the same undo step and drives the stacks.
class HistoryManager {
  final EditingEngine engine;

  /// How long a gap between edits is still considered "the same typing
  /// session" for coalescing purposes. Pausing longer than this before
  /// the next keystroke starts a fresh history entry, same as most
  /// editors' typing-pause heuristic.
  final Duration typingTimeout;

  /// Oldest entries are dropped once the stack exceeds this size, so
  /// history doesn't grow unbounded over a long editing session.
  final int maxHistoryLength;

  final List<EditorCommand> _undoStack = [];
  final List<EditorCommand> _redoStack = [];

  DateTime? _lastEditTime;

  HistoryManager({
    required this.engine,
    this.typingTimeout = const Duration(milliseconds: 800),
    this.maxHistoryLength = 500,
  });

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  int get undoDepth => _undoStack.length;

  int get redoDepth => _redoStack.length;

  /// Applies `command` and records it, coalescing into the current
  /// typing/deleting session when appropriate. This is the only path by
  /// which new commands should reach the engine — going through
  /// [EditingEngine] directly bypasses history entirely.
  EditorSelection execute(EditorCommand command) {
    final selection = command.execute(engine);
    _record(command);
    return selection;
  }

  void _record(EditorCommand command) {
    _redoStack.clear();

    final now = DateTime.now();
    final withinTypingWindow =
        _lastEditTime != null && now.difference(_lastEditTime!) <= typingTimeout;
    _lastEditTime = now;

    if (withinTypingWindow && _undoStack.isNotEmpty) {
      final top = _undoStack.last;
      final mostRecentMember = top is CompositeCommand ? top.commands.last : top;
      if (command.canCoalesceWith(mostRecentMember)) {
        _undoStack[_undoStack.length - 1] =
        top is CompositeCommand ? top.grow(command) : CompositeCommand([top, command]);
        return;
      }
    }

    _undoStack.add(command);
    if (_undoStack.length > maxHistoryLength) {
      _undoStack.removeAt(0);
    }
  }

  /// Call when the caret moves without an accompanying edit (arrow keys,
  /// tapping to reposition, changing selection). Ends the current
  /// coalescing session so the next edit starts a new history entry,
  /// even if it arrives within [typingTimeout].
  void breakCoalescing() {
    _lastEditTime = null;
  }

  /// Reverses the most recent history entry. Returns the resulting
  /// selection, or `null` if there was nothing to undo.
  EditorSelection? undo() {
    if (_undoStack.isEmpty) return null;
    breakCoalescing();
    final command = _undoStack.removeLast();
    final selection = command.undo(engine);
    _redoStack.add(command);
    return selection;
  }

  /// Re-applies the most recently undone entry. Returns the resulting
  /// selection, or `null` if there was nothing to redo.
  EditorSelection? redo() {
    if (_redoStack.isEmpty) return null;
    breakCoalescing();
    final command = _redoStack.removeLast();
    final selection = command.execute(engine);
    _undoStack.add(command);
    return selection;
  }

  /// Discards all history without touching the document. Used when
  /// loading a different note into the same engine — the new note's
  /// history should start clean.
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _lastEditTime = null;
  }
}