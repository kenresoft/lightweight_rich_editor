import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import 'editor_command.dart';

class _HeaderSnapshot {
  final int start;
  final int end;
  final String? headerLevel;
  const _HeaderSnapshot(this.start, this.end, this.headerLevel);
}

/// Sets `headerLevel` on the paragraph(s) containing `selection`, via
/// [EditingEngine.setHeaderLevel]. Snapshots each affected paragraph's
/// prior header level individually, since a multi-paragraph selection
/// can span several different previous values.
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