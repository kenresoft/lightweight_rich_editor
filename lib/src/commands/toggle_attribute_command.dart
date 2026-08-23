import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Toggles `type` over `selection`, via [EditingEngine.toggleAttribute].
///
/// Toggling twice does not, in general, undo itself (a partially-bold
/// selection becomes fully bold, not toggled off), so [execute] snapshots
/// the exact spans of `type` intersecting `selection` and [undo] restores
/// that snapshot rather than toggling again.
class ToggleAttributeCommand extends EditorCommand {
  final AttributeType type;
  final EditorSelection selection;

  List<TextAttribute>? _previousSpans;

  ToggleAttributeCommand(this.type, this.selection) : assert(type.isToggle);

  @override
  bool get isFormattingChange => true;

  @override
  EditorSelection execute(EditingEngine engine) {
    _previousSpans =
        engine.document.attributeStore.findIntersecting(selection.start, selection.end, type: type);
    engine.toggleAttribute(type, selection);
    return selection;
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      final store = engine.document.attributeStore;
      store.clearRange(selection.start, selection.end, type: type);
      for (final span in _previousSpans ?? const <TextAttribute>[]) {
        store.insert(span);
      }
      store.optimize(type: type);
      engine.transactions.notify();
      return selection;
    });
  }
}