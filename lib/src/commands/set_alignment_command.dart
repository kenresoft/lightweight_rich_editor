import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/paragraph_alignment.dart';
import 'editor_command.dart';

/// One paragraph's `alignment` immediately before a
/// [SetAlignmentCommand] ran — enough to restore that exact paragraph's
/// prior state on undo. Same shape as `SetHeaderLevelCommand`'s own
/// `_HeaderSnapshot`, deliberately — see that class for the full
/// reasoning this mirrors.
class _AlignmentSnapshot {
  final int start;
  final int end;
  final ParagraphAlignment? alignment;
  const _AlignmentSnapshot(this.start, this.end, this.alignment);
}

/// Sets `alignment` on the paragraph(s) containing `selection`, via
/// [EditingEngine.setAlignment]. Structural copy of
/// `SetHeaderLevelCommand` — see that class's doc comment for the full
/// reasoning (per-paragraph undo snapshots, since a multi-paragraph
/// selection can have several different previous alignments; snapshot
/// taken inside [execute], not the constructor, since [execute] also
/// runs on redo).
///
/// See [ParagraphAlignment]'s doc comment for the one thing that isn't
/// shared with header: this has no live rendering effect in the editor
/// today, only stored + round-tripped state.
class SetAlignmentCommand extends EditorCommand {
  final EditorSelection selection;
  final ParagraphAlignment? alignment;

  List<_AlignmentSnapshot>? _previous;

  SetAlignmentCommand(this.selection, this.alignment);

  @override
  bool get isFormattingChange => true;

  @override
  EditorSelection execute(EditingEngine engine) {
    final range = engine.paragraphBoundsFor(selection);
    _previous = engine.document.paragraphs
        .recordsOverlapping(range.start, range.end)
        .map((r) => _AlignmentSnapshot(r.start, r.end, r.alignment))
        .toList(growable: false);
    engine.setAlignment(selection, alignment);
    return selection;
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      for (final snapshot in _previous ?? const <_AlignmentSnapshot>[]) {
        engine.document.paragraphs.setAlignment(snapshot.start, snapshot.end, snapshot.alignment);
      }
      engine.transactions.notify();
      return selection;
    });
  }
}
