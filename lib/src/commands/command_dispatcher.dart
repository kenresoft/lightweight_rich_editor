import '../commands/apply_attribute_command.dart';
import '../commands/clear_formatting_command.dart';
import '../commands/composite_command.dart';
import '../commands/editor_command.dart';
import '../commands/renumber_lists_command.dart';
import '../commands/replace_range_command.dart';
import '../commands/set_alignment_command.dart';
import '../commands/set_header_level_command.dart';
import '../commands/set_text_direction_command.dart';
import '../commands/toggle_attribute_command.dart';
import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../history/history_manager.dart';
import '../models/attribute_type.dart';
import '../models/code_block.dart';
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
      final exit = exitCodeBlock(selection);
      if (exit != null) return exit;
      // Use relativeAttributes, not attributesForInsertion: the edit may
      // reconstruct pre-existing text (renumbered subsequent items) that
      // must keep its own formatting rather than inheriting sticky
      // attributes across the whole thing.
      final edit = engine.enterKeyEditWithRenumber(selection, Map.of(engine.stickyAttributes));
      return dispatchRenumbered(
        ReplaceRangeCommand(
          start: edit.start,
          end: edit.end,
          text: edit.text,
          relativeAttributes: edit.relativeAttributes,
          stripAttributes: engine.stickyOff,
        ),
        from: edit.start,
        to: edit.end,
        caret: edit.start + edit.cursorOffsetFromStart,
      );
    }
    return dispatch(ReplaceRangeCommand(
      start: selection.start,
      end: selection.end,
      text: text,
      attributesForInsertion: Map.of(engine.stickyAttributes),
      stripAttributes: engine.stickyOff,
    ));
  }

  /// Enter on the empty last line of a code block: empties the line and makes it
  /// a normal paragraph (one undo step). Returns the caret, or `null` when
  /// [selection] is not in that situation.
  EditorSelection? exitCodeBlock(EditorSelection selection) {
    final exit = engine.codeExitEdit(selection);
    if (exit == null) return null;
    final commands = <EditorCommand>[
      if (exit.end > exit.start) ReplaceRangeCommand(start: exit.start, end: exit.end, text: ''),
      SetHeaderLevelCommand(EditorSelection.collapsed(exit.start), null),
    ];
    dispatch(commands.length == 1 ? commands.first : CompositeCommand(commands));
    return EditorSelection.collapsed(exit.start);
  }

  /// Runs [main], an edit at `[from, to)`, and, when it touches a list, the renumbering of the
  /// lists around it ([RenumberListsCommand]) as the same undo step. [caret] is where the caret
  /// is after [main]; the result is where it is once the numbers are right. An edit away from any
  /// list is a plain command, so typing still groups into one undo step as it always did.
  EditorSelection dispatchRenumbered(
    EditorCommand main, {
    required int from,
    required int to,
    required int caret,
  }) {
    if (!engine.touchesList(from, to)) {
      dispatch(main);
      return EditorSelection.collapsed(caret);
    }
    return dispatch(CompositeCommand([main, RenumberListsCommand(around: caret, caret: caret)]));
  }

  /// Deletes `selection`. A selection spanning list items leaves the numbers after it right, in
  /// the same undo step.
  EditorSelection deleteSelection(EditorSelection selection) {
    if (selection.isCollapsed) return selection;
    final end = engine.endOutsideMarker(selection.end);
    return dispatchRenumbered(
      ReplaceRangeCommand(start: selection.start, end: end, text: ''),
      from: selection.start,
      to: end,
      caret: selection.start,
    );
  }

  /// Deletes one character/list-marker backward from a collapsed caret,
  /// via [EditingEngine.deleteBackwardEdit].
  EditorSelection deleteBackward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteSelection(selection);
    final edit = engine.deleteBackwardEdit(selection);
    if (edit == null) return selection;
    return dispatchRenumbered(
      ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes),
      from: edit.start,
      to: edit.end,
      caret: edit.start + edit.cursorOffsetFromStart,
    );
  }

  /// Deletes one character/list-marker forward from a collapsed caret,
  /// via [EditingEngine.deleteForwardEdit].
  EditorSelection deleteForward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteSelection(selection);
    final edit = engine.deleteForwardEdit(selection);
    if (edit == null) return selection;
    return dispatchRenumbered(
      ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes),
      from: edit.start,
      to: edit.end,
      caret: edit.start,
    );
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

  /// `level` is e.g. `'h1'`/`'h2'`/`'h3'`; `null` clears the header. Applies to
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
    return _dispatchListEdit(selection, edit);
  }

  /// The Checklist button: lines that are not checklist items become unchecked ones, and when
  /// every line already is one the boxes are taken off. Never ticks or unticks an item (that is
  /// [toggleTaskItem], what tapping the box does).
  EditorSelection toggleChecklist(EditorSelection selection) {
    final edit = engine.checklistToggleEdit(selection);
    if (edit == null) return selection;
    return _dispatchListEdit(selection, edit);
  }

  /// Ticks or unticks the checklist item(s) `selection` spans; a line that is not a checklist
  /// item becomes an unchecked one.
  EditorSelection toggleTaskItem(EditorSelection selection) {
    final edit = engine.toggleCheckedEdit(selection);
    if (edit == null) return selection;
    return _dispatchListEdit(selection, edit);
  }

  /// Applies a list edit. A line that becomes a list item stops being a heading, in the same
  /// undo step: a heading and a list marker on one line is never what was meant, and the heading
  /// size would otherwise stay on the first item of the list. (Lines that already are list items,
  /// and code blocks, are left as they are.)
  EditorSelection _dispatchListEdit(
    EditorSelection selection,
    ({int start, int end, String text, List<TextAttribute> relativeAttributes}) edit,
  ) {
    final bounds = engine.paragraphBoundsFor(selection);
    final text = engine.document.text;
    final headings = [
      for (final r in engine.document.paragraphs.recordsOverlapping(bounds.start, bounds.end))
        if (r.headerLevel != null && !isCodeBlockLevel(r.headerLevel) && listPrefixLength(text, r.start) == 0) r,
    ];
    final replace = ReplaceRangeCommand(
      start: edit.start,
      end: edit.end,
      text: edit.text,
      relativeAttributes: edit.relativeAttributes,
    );
    final caret = edit.start + edit.text.length;
    return dispatch(CompositeCommand([
      for (final r in headings) SetHeaderLevelCommand(EditorSelection.collapsed(r.start), null),
      replace,
      // Whatever kind the lines are now, the numbers around them count properly.
      RenumberListsCommand(around: caret, caret: caret),
    ]));
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
    final caret = edit.start + edit.text.length;
    return dispatch(CompositeCommand([
      ReplaceRangeCommand(start: edit.start, end: edit.end, text: edit.text, relativeAttributes: edit.relativeAttributes),
      // A nested numbered item starts again at 1 and the items after it close the gap.
      RenumberListsCommand(around: caret, caret: caret),
    ]));
  }

  /// Tab / Shift+Tab inside a code block: indent or outdent by two spaces (see
  /// [EditingEngine.codeIndentEdits]) as one undo step. A no-op outside code.
  EditorSelection indentCode(EditorSelection selection, {bool outdent = false}) {
    final plan = engine.codeIndentEdits(selection, outdent: outdent);
    if (plan == null) return selection;
    final commands = [
      for (final e in plan.edits) ReplaceRangeCommand(start: e.start, end: e.end, text: e.text),
    ];
    dispatch(commands.length == 1 ? commands.first : CompositeCommand(commands));
    return plan.selection;
  }

  /// Edits the link over `[start, end)`: sets its visible [text] (when it
  /// differs) and its [url] (`null` removes the link) as one undo step. Returns
  /// the selection covering the edited text.
  EditorSelection editLink(int start, int end, String text, String? url) {
    final current = engine.document.text.substring(start, end);
    final newEnd = start + text.length;
    final target = EditorSelection(baseOffset: start, extentOffset: newEnd);
    final commands = <EditorCommand>[
      if (text != current) ReplaceRangeCommand(start: start, end: end, text: text),
      ApplyAttributeCommand(AttributeType.link, target, url),
    ];
    dispatch(commands.length == 1 ? commands.first : CompositeCommand(commands));
    return target;
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