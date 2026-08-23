import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../core/paragraph_record.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Removes every attribute from `selection`, or — at a collapsed caret —
/// clears pending sticky formatting instead. Snapshots whichever of
/// those it's about to clear so [undo] can restore it exactly, including
/// any literal list-marker text `clearFormatting` rewrites.
class ClearFormattingCommand extends EditorCommand {
  final EditorSelection selection;

  List<TextAttribute>? _previousSpans;
  Map<AttributeType, Object?>? _previousSticky;
  List<ParagraphRecord>? _previousBlockMetadata;
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
      _previousBlockMetadata =
          engine.document.paragraphs.recordsOverlapping(selection.start, selection.end);

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
      // Restore text first so later offsets line up with the pre-clear document.
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
      engine.document.paragraphs.restoreBlockMetadata(_previousBlockMetadata ?? const []);
      engine.transactions.notify();
      return selection;
    });
  }
}