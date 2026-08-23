import '../commands/apply_attribute_command.dart';
import '../commands/clear_formatting_command.dart';
import '../commands/editor_command.dart';
import '../commands/replace_range_command.dart';
import '../commands/set_alignment_command.dart';
import '../commands/set_header_level_command.dart';
import '../commands/set_text_direction_command.dart';
import '../commands/toggle_attribute_command.dart';
import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../history/history_manager.dart';
import '../models/attribute_type.dart';
import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';

/// The single entry point every editing action goes through — toolbar
/// buttons, keyboard shortcuts, and paste handling all call
/// `dispatcher.someAction(...)` rather than constructing commands or
/// touching [EditingEngine] / [HistoryManager] directly.
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
  ///
  /// A bare `'\n'` is routed through
  /// [EditingEngine.enterKeyEditWithRenumber] so a programmatic Enter
  /// gets the same list-continuation and renumbering behavior live
  /// typing does.
  EditorSelection insertText(EditorSelection selection, String text) {
    if (text == '\n') {
      // Use relativeAttributes, not attributesForInsertion: the edit may
      // reconstruct pre-existing text (renumbered subsequent items) that
      // must keep its own formatting rather than inheriting sticky
      // attributes across the whole thing.
      final edit = engine.enterKeyEditWithRenumber(selection, Map.of(engine.stickyAttributes));
      dispatch(ReplaceRangeCommand(
        start: edit.start,
        end: edit.end,
        text: edit.text,
        relativeAttributes: edit.relativeAttributes,
      ));
      return EditorSelection.collapsed(edit.start + edit.cursorOffsetFromStart);
    }
    return dispatch(ReplaceRangeCommand(
      start: selection.start,
      end: selection.end,
      text: text,
      attributesForInsertion: Map.of(engine.stickyAttributes),
    ));
  }

  /// Deletes `selection`, then runs [EditingEngine.repairListNumbering]
  /// as a follow-up check so a selection spanning list items doesn't
  /// leave subsequent numbered items with stale numbers.
  ///
  /// When a repair is needed this is two separate undo steps: undoing
  /// once reverts the repair, undoing again removes the deletion.
  EditorSelection deleteSelection(EditorSelection selection) {
    if (selection.isCollapsed) return selection;
    final result = dispatch(ReplaceRangeCommand(start: selection.start, end: selection.end, text: ''));
    return _repairNumberingIfNeeded(result);
  }

  EditorSelection _repairNumberingIfNeeded(EditorSelection resultSelection) {
    final edit = engine.repairListNumbering(resultSelection);
    if (edit == null) return resultSelection;
    dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes));
    return resultSelection;
  }

  /// Deletes one character/list-marker backward from a collapsed caret,
  /// via [EditingEngine.deleteBackwardEdit].
  EditorSelection deleteBackward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteSelection(selection);
    final edit = engine.deleteBackwardEdit(selection);
    if (edit == null) return selection;
    dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes));
    return EditorSelection.collapsed(edit.start + edit.cursorOffsetFromStart);
  }

  /// Deletes one character/list-marker forward from a collapsed caret,
  /// via [EditingEngine.deleteForwardEdit].
  EditorSelection deleteForward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteSelection(selection);
    final edit = engine.deleteForwardEdit(selection);
    if (edit == null) return selection;
    dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes));
    return EditorSelection.collapsed(edit.start);
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

  /// Sets a value-carrying attribute (color, size, link). `value: null`
  /// removes it. Not for header — see [setHeader].
  void apply(AttributeType type, EditorSelection selection, Object? value) {
    assert(type != AttributeType.header, 'use setHeader, not apply, for header');
    dispatch(ApplyAttributeCommand(type, selection, value));
  }

  void setColor(EditorSelection selection, int? argb) => apply(AttributeType.color, selection, argb);

  void setSize(EditorSelection selection, num? size) => apply(AttributeType.size, selection, size);

  void setLink(EditorSelection selection, String? url) => apply(AttributeType.link, selection, url);

  /// `level` is e.g. `'h1'`/`'h2'`; `null` clears the header. Applies to
  /// the whole paragraph containing `selection`.
  void setHeader(EditorSelection selection, String? level) {
    dispatch(SetHeaderLevelCommand(selection, level));
  }

  /// `alignment` is `null` (default/left), `center`, or `right`. Applies
  /// to the whole paragraph containing `selection`.
  void setAlignment(EditorSelection selection, ParagraphAlignment? alignment) {
    dispatch(SetAlignmentCommand(selection, alignment));
  }

  /// `textDirection` is `null` (unspecified), `ltr`, or `rtl`. Applies to
  /// the whole paragraph containing `selection`.
  void setTextDirection(EditorSelection selection, ParagraphTextDirection? textDirection) {
    dispatch(SetTextDirectionCommand(selection, textDirection));
  }

  /// Toggles a literal `'- '` prefix on the paragraph containing
  /// `selection.start`.
  EditorSelection toggleBulletList(EditorSelection selection) => _toggleList(selection, ParagraphListType.bullet);

  /// Toggles a literal `'1. '` prefix on the paragraph containing
  /// `selection.start`.
  EditorSelection toggleNumberedList(EditorSelection selection) => _toggleList(selection, ParagraphListType.numbered);

  // List "formatting" is literal text (see EditingEngine.listToggleEdit),
  // so this dispatches a ReplaceRangeCommand like any other text edit
  // rather than a bespoke Command. Returns the resulting selection since,
  // unlike toggleBold etc., it changes text length.
  EditorSelection _toggleList(EditorSelection selection, ParagraphListType type) {
    final edit = engine.listToggleEdit(selection, type);
    if (edit == null) return selection;
    return dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes));
  }

  /// Toggles task-list checkbox state on the paragraph(s) `selection`
  /// spans.
  EditorSelection toggleTaskItem(EditorSelection selection) {
    final edit = engine.toggleCheckedEdit(selection);
    if (edit == null) return selection;
    return dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes));
  }

  /// Indents the list item containing `selection.start` by inserting 2
  /// literal leading spaces. No-op if that paragraph has no list prefix.
  EditorSelection indentList(EditorSelection selection) => _listIndent(selection, outdent: false);

  /// Outdents the list item containing `selection.start` by removing up
  /// to 2 leading spaces. No-op if already at the top level, or if that
  /// paragraph has no list prefix.
  EditorSelection outdentList(EditorSelection selection) => _listIndent(selection, outdent: true);

  EditorSelection _listIndent(EditorSelection selection, {required bool outdent}) {
    final edit = engine.listIndentEdit(selection, outdent: outdent);
    if (edit == null) return selection;
    return dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes));
  }

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