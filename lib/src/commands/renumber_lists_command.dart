import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import 'editor_command.dart';
import 'replace_range_command.dart';

/// Makes the numbered lists around [around] count properly again (see
/// [EditingEngine.renumberEdits]). It is meant to follow a list edit inside one
/// [CompositeCommand], so the edit and the renumbering are a single undo step: the edit only has
/// to put the right kind of marker on the right line, and this settles the numbers however the
/// lines are nested.
///
/// What to change is worked out when the command runs, not when it is built, because it runs
/// again on redo. [caret] is where the caret is after the edit before it; the result is where it
/// is after the digits change (a new "10." is a character longer than "9.").
class RenumberListsCommand extends EditorCommand {
  RenumberListsCommand({required this.around, required this.caret});

  final int around;
  final int caret;

  final List<ReplaceRangeCommand> _applied = [];

  @override
  EditorSelection execute(EditingEngine engine) {
    return engine.transactions.run(() {
      _applied.clear();
      var shift = 0;
      // Highest position first: an edit never moves the ones still to come.
      for (final edit in engine.renumberEdits(around)) {
        final command = ReplaceRangeCommand(
          start: edit.start,
          end: edit.end,
          text: edit.text,
          relativeAttributes: const [],
        );
        command.execute(engine);
        _applied.add(command);
        if (edit.end <= caret) shift += edit.text.length - (edit.end - edit.start);
      }
      return EditorSelection.collapsed(caret + shift);
    });
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      for (final command in _applied.reversed) {
        command.undo(engine);
      }
      return EditorSelection.collapsed(caret);
    });
  }
}
