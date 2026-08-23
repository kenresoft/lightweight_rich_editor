import '../core/editing_engine.dart';
import '../core/editor_selection.dart';

/// A single undoable editing operation.
///
/// Every user-facing edit (typing, toggling formatting, pasting, clearing
/// formatting) is a command, so undo/redo and keyboard shortcuts all go
/// through one path.
///
/// A command must capture whatever pre-edit state it needs to reverse
/// itself *inside* [execute], not at construction time, since [execute]
/// also runs on redo.
abstract class EditorCommand {
  /// Applies this command to `engine` and returns the resulting
  /// selection. Also called on redo.
  EditorSelection execute(EditingEngine engine);

  /// Reverses this command's effect on `engine` and returns the
  /// resulting (pre-edit) selection.
  EditorSelection undo(EditingEngine engine);

  /// Whether this command represents a formatting change rather than a
  /// text change.
  bool get isFormattingChange => false;

  /// Whether this command may be grouped into the same undo step as
  /// `previous`, the command immediately before it in the current undo
  /// group. Used for typing/backspace coalescing.
  ///
  /// Default: never coalesces.
  bool canCoalesceWith(EditorCommand previous) => false;
}