import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Removes every attribute from `selection`, or — at a collapsed caret —
/// clears pending sticky formatting instead. Snapshots whichever of
/// those it's about to clear so [undo] can restore it exactly.
///
/// Also clears `headerLevel` on every paragraph `selection` overlaps —
/// header lives in `ParagraphIndex` now, not `AttributeStore` (see the
/// block-architecture design notes), so `EditingEngine.clearFormatting`
/// has to reach it separately from the inline-attribute clearing
/// `_previousSpans` already covers. Uses the selection's exact bounds,
/// not a paragraph-bounds-expanded range — matching how clearing every
/// other attribute type already only touches what the selection
/// literally overlaps, not the whole enclosing paragraph. `headerLevel`
/// is never part of `stickyAttributes`, so the collapsed-selection
/// branch is unaffected — clearing formatting at a bare caret has never
/// retroactively un-headed the current paragraph, and still doesn't.
class ClearFormattingCommand extends EditorCommand {
  final EditorSelection selection;

  List<TextAttribute>? _previousSpans;
  Map<AttributeType, Object?>? _previousSticky;
  List<({int start, int end, String? headerLevel})>? _previousHeaderLevels;

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
      for (final snapshot in _previousHeaderLevels ?? const []) {
        engine.document.paragraphs.setHeaderLevel(snapshot.start, snapshot.end, snapshot.headerLevel);
      }
      engine.transactions.notify();
      return selection;
    });
  }
}