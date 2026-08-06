import '../commands/apply_attribute_command.dart';
import '../commands/clear_formatting_command.dart';
import '../commands/editor_command.dart';
import '../commands/replace_range_command.dart';
import '../commands/toggle_attribute_command.dart';
import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../history/history_manager.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';

/// The single entry point every editing action goes through — toolbar
/// buttons, keyboard shortcuts, paste handling, and (later) AI-driven
/// edits or automation should all call `dispatcher.someAction(...)`
/// rather than constructing commands or touching [EditingEngine] /
/// [HistoryManager] themselves.
///
/// This is what makes "clean undo, keyboard shortcuts, AI editing,
/// automation, future extensibility" (the brief's justification for a
/// command system) actually true in practice rather than just in
/// principle: there's exactly one place that knows how to turn "the user
/// wants to toggle bold" into a recorded, undoable operation.
class CommandDispatcher {
  final EditingEngine engine;
  final HistoryManager history;

  CommandDispatcher({required this.engine, required this.history});

  EditorSelection dispatch(EditorCommand command) => history.execute(command);

  // ---------------------------------------------------------------------
  // Text editing
  // ---------------------------------------------------------------------

  /// Inserts `text` at `selection` (replacing it, if not collapsed),
  /// formatted with whatever sticky attributes are currently pending.
  EditorSelection insertText(EditorSelection selection, String text) {
    return dispatch(ReplaceRangeCommand(
      start: selection.start,
      end: selection.end,
      text: text,
      attributesForInsertion: Map.of(engine.stickyAttributes),
    ));
  }

  EditorSelection deleteSelection(EditorSelection selection) {
    if (selection.isCollapsed) return selection;
    return dispatch(ReplaceRangeCommand(start: selection.start, end: selection.end, text: ''));
  }

  EditorSelection deleteBackward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteSelection(selection);
    if (selection.start == 0) return selection;
    return dispatch(ReplaceRangeCommand(start: selection.start - 1, end: selection.start, text: ''));
  }

  EditorSelection deleteForward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteSelection(selection);
    if (selection.start >= engine.document.length) return selection;
    return dispatch(ReplaceRangeCommand(start: selection.start, end: selection.start + 1, text: ''));
  }

  /// Plain-text paste — same as [insertText], named for call-site clarity.
  EditorSelection paste(EditorSelection selection, String text) => insertText(selection, text);

  /// Rich paste: `text` with its own formatting (`relativeAttributes`,
  /// expressed relative to the start of `text`) rather than inheriting
  /// sticky formatting from the caret.
  EditorSelection pasteRich(
      EditorSelection selection,
      String text,
      List<TextAttribute> relativeAttributes,
      ) {
    return dispatch(ReplaceRangeCommand(
      start: selection.start,
      end: selection.end,
      text: text,
      relativeAttributes: relativeAttributes,
    ));
  }

  // ---------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------

  void toggleBold(EditorSelection selection) => toggle(AttributeType.bold, selection);
  void toggleItalic(EditorSelection selection) => toggle(AttributeType.italic, selection);
  void toggleUnderline(EditorSelection selection) => toggle(AttributeType.underline, selection);
  void toggleStrikethrough(EditorSelection selection) =>
      toggle(AttributeType.strikethrough, selection);
  void toggleHighlight(EditorSelection selection) => toggle(AttributeType.highlight, selection);
  void toggleCode(EditorSelection selection) => toggle(AttributeType.code, selection);

  void toggle(AttributeType type, EditorSelection selection) {
    dispatch(ToggleAttributeCommand(type, selection));
  }

  /// Sets a value-carrying attribute (color, size, link, header).
  /// `value: null` removes it.
  void apply(AttributeType type, EditorSelection selection, Object? value) {
    dispatch(ApplyAttributeCommand(type, selection, value));
  }

  void setColor(EditorSelection selection, int? argb) => apply(AttributeType.color, selection, argb);

  void setSize(EditorSelection selection, num? size) => apply(AttributeType.size, selection, size);

  void setLink(EditorSelection selection, String? url) => apply(AttributeType.link, selection, url);

  /// `level` is e.g. `'h1'`/`'h2'`; `null` clears the header. Applies to
  /// the whole paragraph containing `selection`, not just the selected
  /// text — see [AttributeType.isParagraphScoped].
  void setHeader(EditorSelection selection, String? level) =>
      apply(AttributeType.header, selection, level);

  void clearFormatting(EditorSelection selection) {
    dispatch(ClearFormattingCommand(selection));
  }

  // ---------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------

  bool get canUndo => history.canUndo;

  bool get canRedo => history.canRedo;

  /// Returns the resulting selection, or `null` if there was nothing to
  /// undo.
  EditorSelection? undo() => history.undo();

  /// Returns the resulting selection, or `null` if there was nothing to
  /// redo.
  EditorSelection? redo() => history.redo();
}