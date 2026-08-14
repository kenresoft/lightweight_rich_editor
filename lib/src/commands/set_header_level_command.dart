import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import 'editor_command.dart';

/// One paragraph's `headerLevel` immediately before a
/// [SetHeaderLevelCommand] ran — enough to restore that exact
/// paragraph's prior state on undo.
class _HeaderSnapshot {
  final int start;
  final int end;
  final String? headerLevel;
  const _HeaderSnapshot(this.start, this.end, this.headerLevel);
}

/// Sets `headerLevel` on the paragraph(s) containing `selection`, via
/// [EditingEngine.setHeaderLevel]. `AttributeType.header` no longer
/// drives anything — this command (and `ParagraphIndex` underneath it)
/// is header's entire live representation now; see the block-
/// architecture design notes and `ParagraphIndex`'s own doc comment.
///
/// Unlike the old `AttributeStore`-based header path — where a
/// multi-paragraph selection collapsed to one span with one shared
/// "previous value" — `ParagraphIndex` tracks `headerLevel` per
/// paragraph, so a selection spanning several paragraphs can have
/// several *different* previous header levels. Undo has to restore each
/// paragraph's own prior value individually, not one shared snapshot;
/// that's what [_previous] holds one entry per affected paragraph for.
///
/// Snapshotting happens inside [execute], not the constructor — same
/// reason every other command does that: [execute] also runs on redo,
/// and by the time it's called again the document is back in its
/// pre-edit state, which is exactly the state that needs capturing.
class SetHeaderLevelCommand extends EditorCommand {
  final EditorSelection selection;
  final String? headerLevel;

  List<_HeaderSnapshot>? _previous;

  SetHeaderLevelCommand(this.selection, this.headerLevel);

  @override
  bool get isFormattingChange => true;

  @override
  EditorSelection execute(EditingEngine engine) {
    final range = engine.paragraphBoundsFor(selection);
    _previous = engine.document.paragraphs
        .recordsOverlapping(range.start, range.end)
        .map((r) => _HeaderSnapshot(r.start, r.end, r.headerLevel))
        .toList(growable: false);
    engine.setHeaderLevel(selection, headerLevel);
    return selection;
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      for (final snapshot in _previous ?? const <_HeaderSnapshot>[]) {
        engine.document.paragraphs.setHeaderLevel(snapshot.start, snapshot.end, snapshot.headerLevel);
      }
      engine.transactions.notify();
      return selection;
    });
  }
}