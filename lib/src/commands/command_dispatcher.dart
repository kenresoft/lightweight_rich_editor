import '../commands/apply_attribute_command.dart';
import '../commands/clear_formatting_command.dart';
import '../commands/editor_command.dart';
import '../commands/replace_range_command.dart';
import '../commands/set_header_level_command.dart';
import '../commands/toggle_attribute_command.dart';
import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../history/history_manager.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';

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
  ///
  /// A bare `'\n'` — a single-character insertion — is routed through
  /// [EditingEngine.enterKeyEditWithRenumber], so a programmatic Enter
  /// (e.g. from a toolbar/shortcut, as opposed to live typing, which
  /// `RichEditorController.set value` handles separately) gets the same
  /// list-continuation and numbered-list-renumbering behavior live
  /// typing does.
  EditorSelection insertText(EditorSelection selection, String text) {
    if (text == '\n') {
      final edit = engine.enterKeyEditWithRenumber(selection);
      dispatch(ReplaceRangeCommand(
        start: edit.start,
        end: edit.end,
        text: edit.text,
        attributesForInsertion: Map.of(engine.stickyAttributes),
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

  EditorSelection deleteSelection(EditorSelection selection) {
    if (selection.isCollapsed) return selection;
    return dispatch(ReplaceRangeCommand(start: selection.start, end: selection.end, text: ''));
  }

  /// Previously constructed its own hardcoded single-character
  /// deletion here, entirely bypassing `EditingEngine.deleteBackward`'s
  /// smart list-marker/renumbering logic — a real bug, not a deliberate
  /// scope choice. Now routes through `EditingEngine.deleteBackwardEdit`
  /// like every other computed edit in this class.
  EditorSelection deleteBackward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteSelection(selection);
    final edit = engine.deleteBackwardEdit(selection);
    if (edit == null) return selection;
    dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text));
    return EditorSelection.collapsed(edit.start + edit.cursorOffsetFromStart);
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
  /// the whole paragraph containing `selection`, not just the selected
  /// text.
  ///
  /// Dispatches [SetHeaderLevelCommand], not [ApplyAttributeCommand] —
  /// `AttributeType.header` is no longer written to anywhere in the live
  /// editing path (see the block-architecture design notes); header is
  /// entirely a `ParagraphIndex` concern now, with its own undo
  /// semantics `SetHeaderLevelCommand` implements (per-paragraph
  /// snapshotting, since a multi-paragraph selection can have several
  /// different previous header levels — `ApplyAttributeCommand`'s single
  /// shared previous-value undo couldn't represent that correctly).
  void setHeader(EditorSelection selection, String? level) {
    dispatch(SetHeaderLevelCommand(selection, level));
  }

  /// Toggles a literal `'- '` prefix on the paragraph containing
  /// `selection.start`.
  EditorSelection toggleBulletList(EditorSelection selection) => _toggleList(selection, ParagraphListType.bullet);

  /// Toggles a literal `'1. '` prefix on the paragraph containing
  /// `selection.start`.
  EditorSelection toggleNumberedList(EditorSelection selection) => _toggleList(selection, ParagraphListType.numbered);

  /// Toggles a literal list prefix on the paragraph containing
  /// `selection.start`, as one undoable text edit via the exact same
  /// [ReplaceRangeCommand] every other text edit uses. This is
  /// deliberately not a separate formatting command like [setHeader] —
  /// list "formatting" here IS text (see
  /// [EditingEngine.listToggleEdit]'s doc comment): inserting or
  /// removing `'- '`/`'1. '` is exactly the same kind of edit as typing
  /// those characters by hand, so it goes through the same path typing
  /// does, not a bespoke Command.
  ///
  /// Returns the resulting `EditorSelection`, unlike [toggle] (bold,
  /// italic, ...): those never change text *length*, so
  /// `RichEditorController._handleCommit`'s clamped-selection guess is
  /// already correct for them and callers don't need to sync explicitly.
  /// This does change length — inserting/removing prefix characters —
  /// so the caller needs to sync selection the same way [insertText]/
  /// [deleteBackward] do, not the way [toggleBold] does.
  ///
  /// Only affects the single paragraph `selection.start` is in. A
  /// selection spanning multiple paragraphs would need several such
  /// edits — each one shifting every subsequent offset — collapsed into
  /// one undo step. That needs a batched/composite command mechanism
  /// (this library has one for `SearchIndex.replaceAll`, per earlier
  /// notes, but I haven't reviewed that source), so multi-paragraph
  /// toggling is deliberately not implemented here rather than guessed
  /// at.
  EditorSelection _toggleList(EditorSelection selection, ParagraphListType type) {
    final edit = engine.listToggleEdit(selection, type);
    if (edit == null) return selection;
    return dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text));
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
    return dispatch(ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text));
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