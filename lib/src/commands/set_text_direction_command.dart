import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/paragraph_text_direction.dart';
import 'editor_command.dart';

class _TextDirectionSnapshot {
  final int start;
  final int end;
  final ParagraphTextDirection? textDirection;
  const _TextDirectionSnapshot(this.start, this.end, this.textDirection);
}

/// Sets `textDirection` on the paragraph(s) containing `selection`, via
/// [EditingEngine.setTextDirection]. Snapshots each affected paragraph's
/// prior direction individually, since a multi-paragraph selection can
/// span several different previous values.
class SetTextDirectionCommand extends EditorCommand {
  final EditorSelection selection;
  final ParagraphTextDirection? textDirection;

  List<_TextDirectionSnapshot>? _previous;

  SetTextDirectionCommand(this.selection, this.textDirection);

  @override
  bool get isFormattingChange => true;

  @override
  EditorSelection execute(EditingEngine engine) {
    final range = engine.paragraphBoundsFor(selection);
    _previous = engine.document.paragraphs
        .recordsOverlapping(range.start, range.end)
        .map((r) => _TextDirectionSnapshot(r.start, r.end, r.textDirection))
        .toList(growable: false);
    engine.setTextDirection(selection, textDirection);
    return selection;
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      for (final snapshot in _previous ?? const <_TextDirectionSnapshot>[]) {
        engine.document.paragraphs.setTextDirection(snapshot.start, snapshot.end, snapshot.textDirection);
      }
      engine.transactions.notify();
      return selection;
    });
  }
}
