import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Removes every attribute from `selection`, or — at a collapsed caret —
/// clears pending sticky formatting instead. Snapshots whichever of
/// those it's about to clear so [undo] can restore it exactly.
class ClearFormattingCommand extends EditorCommand {
  final EditorSelection selection;

  List<TextAttribute>? _previousSpans;
  Map<AttributeType, Object?>? _previousSticky;

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
      final store = engine.document.attributeStore;
      for (final span in _previousSpans ?? const <TextAttribute>[]) {
        store.insert(span);
      }
      store.optimize();
      engine.transactions.notify();
      return selection;
    });
  }
}