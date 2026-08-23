import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import 'editor_command.dart';

/// Several [EditorCommand]s treated as one undo step.
///
/// [HistoryManager] builds these to coalesce sequential typing or
/// backspacing into a single history entry, undoing/redoing the whole
/// group together in one [TransactionManager] batch.
class CompositeCommand extends EditorCommand {
  final List<EditorCommand> commands;

  CompositeCommand(this.commands) : assert(commands.isNotEmpty);

  @override
  bool get isFormattingChange => commands.every((c) => c.isFormattingChange);

  @override
  EditorSelection execute(EditingEngine engine) {
    return engine.transactions.run(() {
      var selection = const EditorSelection.collapsed(0);
      for (final command in commands) {
        selection = command.execute(engine);
      }
      return selection;
    });
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      var selection = const EditorSelection.collapsed(0);
      for (final command in commands.reversed) {
        selection = command.undo(engine);
      }
      return selection;
    });
  }

  /// Returns a new group with `command` appended — used by
  /// [HistoryManager] when an incoming command coalesces with this
  /// group's most recent member.
  CompositeCommand grow(EditorCommand command) => CompositeCommand([...commands, command]);
}