import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/paragraph_text_direction.dart';
import 'editor_command.dart';

/// One paragraph's `textDirection` immediately before a
/// [SetTextDirectionCommand] ran — enough to restore that exact
/// paragraph's prior state on undo. Same shape as `SetAlignmentCommand`'s
/// own `_AlignmentSnapshot`, deliberately — see that class for the full
/// reasoning this mirrors.
class _TextDirectionSnapshot {
  final int start;
  final int end;
  final ParagraphTextDirection? textDirection;
  const _TextDirectionSnapshot(this.start, this.end, this.textDirection);
}

/// Sets `textDirection` on the paragraph(s) containing `selection`, via
/// [EditingEngine.setTextDirection]. Structural copy of
/// `SetAlignmentCommand` — see that class's doc comment for the full
/// reasoning (per-paragraph undo snapshots, since a multi-paragraph
/// selection can have several different previous directions; snapshot
/// taken inside [execute], not the constructor, since [execute] also runs
/// on redo).
///
/// See [ParagraphTextDirection]'s doc comment for the caveat this shares
/// with alignment: stored + round-tripped state, no live rendering effect
/// in the editor today.
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
