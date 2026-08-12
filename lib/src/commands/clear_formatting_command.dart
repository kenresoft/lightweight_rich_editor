import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Removes every attribute from `selection`, or — at a collapsed caret —
/// clears pending sticky formatting instead. Snapshots whichever of
/// those it's about to clear so [undo] can restore it exactly.
///
/// Also snapshots the text `EditingEngine.clearFormattingListEdit` is
/// about to rewrite (stripping literal list markers), if any — this is
/// a real text mutation, unlike the attribute/header clearing, so it
/// needs its own undo path: `_listEditStart`/`_listEditNewLength`
/// record where and how much text `clearFormatting` will have replaced
/// that range with, and `_previousListText` is what to put back.
/// Snapshotting happens in [execute] (before `engine.clearFormatting`
/// actually runs), same principle as [ReplaceRangeCommand]'s own
/// `_removedText`/`_removedSpans` — capture what's about to be
/// overwritten before it is, not try to reconstruct it after the fact.
class ClearFormattingCommand extends EditorCommand {
  final EditorSelection selection;

  List<TextAttribute>? _previousSpans;
  Map<AttributeType, Object?>? _previousSticky;
  List<({int start, int end, String? headerLevel})>? _previousHeaderLevels;
  int? _listEditStart;
  int? _listEditNewLength;
  String? _previousListText;

  ClearFormattingCommand(this.selection);

  @override
  bool get isFormattingChange => true;

  @override
  EditorSelection execute(EditingEngine engine) {
    if (selection.isCollapsed) {
      _previousSticky = Map.of(engine.stickyAttributes);
    } else {
      _previousSpans =
          engine.document.attributeStore.findIntersecting(selection.start, selection.end);
      _previousHeaderLevels = engine.document.paragraphs
          .recordsOverlapping(selection.start, selection.end)
          .map((r) => (start: r.start, end: r.end, headerLevel: r.headerLevel))
          .toList(growable: false);

      final listEdit = engine.clearFormattingListEdit(selection);
      if (listEdit != null) {
        _listEditStart = listEdit.start;
        _listEditNewLength = listEdit.text.length;
        _previousListText = engine.document.text.substring(listEdit.start, listEdit.end);
      }
    }
    engine.clearFormatting(selection);
    return selection;
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    if (selection.isCollapsed) {
      engine.restoreStickyAttributes(_previousSticky ?? const {});
      return selection;
    }
    return engine.transactions.run(() {
      // Text first: _previousHeaderLevels/_previousSpans are in
      // *original* (pre-clear) coordinates, which only line up with the
      // document again once the list-marker strip (if any) has been
      // reversed and paragraph structure is back to what it was.
      if (_listEditStart != null) {
        engine.replaceRange(
          _listEditStart!,
          _listEditStart! + (_listEditNewLength ?? 0),
          _previousListText ?? '',
        );
      }
      final store = engine.document.attributeStore;
      for (final span in _previousSpans ?? const <TextAttribute>[]) {
        store.insert(span);
      }
      store.optimize();
      for (final snapshot in _previousHeaderLevels ?? const []) {
        engine.document.paragraphs.setHeaderLevel(snapshot.start, snapshot.end, snapshot.headerLevel);
      }
      engine.transactions.notify();
      return selection;
    });
  }
}