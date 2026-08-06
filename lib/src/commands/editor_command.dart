import '../core/editing_engine.dart';
import '../core/editor_selection.dart';

/// A single undoable editing operation.
///
/// Every user-facing edit — typing a character, toggling bold, pasting,
/// clearing formatting — is a command. That uniformity is what makes
/// undo/redo, keyboard shortcuts, and future automation (AI rewrites,
/// scripted edits) all go through one path instead of each needing its
/// own bespoke history-recording code, which is what the old controller
/// had.
///
/// A command is responsible for capturing whatever pre-edit state it
/// needs to reverse itself *inside* [execute] — not at construction time
/// — since [execute] is also what runs on redo, and the document must be
/// back in its pre-edit state by the time redo calls it again.
abstract class EditorCommand {
  /// Applies this command to `engine` and returns the resulting
  /// selection. Also called on redo.
  EditorSelection execute(EditingEngine engine);

  /// Reverses this command's effect on `engine` and returns the
  /// resulting (pre-edit) selection.
  EditorSelection undo(EditingEngine engine);

  /// Whether this command represents a formatting change (bold, color,
  /// header, ...) rather than a text change. Formatting changes always
  /// get their own history entry — see [HistoryManager] — so this exists
  /// mainly for [EditorMetrics] (Phase 6) to report undo-stack
  /// composition, not for coalescing decisions.
  bool get isFormattingChange => false;

  /// Whether this command may be grouped into the same undo step as
  /// `previous`, the command immediately before it in the current undo
  /// group. Used for typing and backspace coalescing — sequential
  /// character-by-character edits becoming one undo step, VS
  /// Code/Notion/Apple-Notes-style.
  ///
  /// Default: never coalesces. Only [ReplaceRangeCommand] overrides this,
  /// and only for pure inserts or pure deletes — formatting commands and
  /// paste/rich-paste always stand alone, matching "formatting changes
  /// create separate history events" from the product brief.
  bool canCoalesceWith(EditorCommand previous) => false;
}