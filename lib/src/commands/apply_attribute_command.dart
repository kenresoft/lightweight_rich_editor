import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Sets `type` to `value` over `selection` (or the enclosing paragraph,
/// for [AttributeType.isParagraphScoped] types like
/// [AttributeType.header]) via [EditingEngine.applyAttribute].
/// `value: null` removes the attribute instead — [EditingEngine] already
/// treats those as the same operation, so this command does too rather
/// than needing a separate `RemoveAttributeCommand`.
///
/// Like [ToggleAttributeCommand], undo restores an exact pre-edit
/// snapshot of the affected range rather than attempting to invert the
/// operation logically.
class ApplyAttributeCommand extends EditorCommand {
  final AttributeType type;
  final EditorSelection selection;
  final Object? value;

  EditorSelection? _affectedRange;
  List<TextAttribute>? _previousSpans;

  ApplyAttributeCommand(this.type, this.selection, this.value);

  @override
  bool get isFormattingChange => true;

  @override
  EditorSelection execute(EditingEngine engine) {
    _affectedRange = engine.effectiveRangeFor(type, selection);
    _previousSpans = engine.document.attributeStore
        .findIntersecting(_affectedRange!.start, _affectedRange!.end, type: type);
    engine.applyAttribute(type, selection, value);
    return selection;
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    final range = _affectedRange;
    if (range == null) return selection;
    return engine.transactions.run(() {
      final store = engine.document.attributeStore;
      store.clearRange(range.start, range.end, type: type);
      for (final span in _previousSpans ?? const <TextAttribute>[]) {
        store.insert(span);
      }
      store.optimize(type: type);
      engine.transactions.notify();
      return selection;
    });
  }
}