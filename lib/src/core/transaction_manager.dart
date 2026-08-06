/// Coalesces change notifications from a batch of edits into a single
/// callback, so a compound operation — paste, an AI rewrite, an import,
/// replace-all, a markdown conversion, bulk formatting — rebuilds the
/// editor's UI once instead of once per underlying edit.
///
/// [EditingEngine] calls [notify] after every mutation it makes. Outside
/// a transaction (`depth == 0`), that fires [onCommit] immediately — a
/// single `engine.insert(...)` call still notifies exactly once, same as
/// today. Inside [run], every [notify] call just marks the batch dirty;
/// [onCommit] fires once, when the outermost [run] call returns.
/// Transactions nest safely: only the outermost one triggers the commit.
class TransactionManager {
  final void Function() onCommit;

  int _depth = 0;
  bool _dirty = false;

  TransactionManager(this.onCommit);

  bool get isInTransaction => _depth > 0;

  /// Runs [action], deferring notification until every (possibly nested)
  /// transaction started inside it has also finished.
  ///
  /// ```dart
  /// transactions.run(() {
  ///   engine.clearFormatting(selection);
  ///   engine.insert(selection, pastedText);
  ///   engine.pasteRich(selection, pastedText, pastedAttributes);
  /// }); // listeners notified once, here
  /// ```
  T run<T>(T Function() action) {
    _depth++;
    try {
      return action();
    } finally {
      _depth--;
      if (_depth == 0 && _dirty) {
        _dirty = false;
        onCommit();
      }
    }
  }

  /// Signals that something changed. Called by [EditingEngine] after
  /// each mutation — callers building compound operations don't need to
  /// call this themselves, only [run].
  void notify() {
    if (_depth > 0) {
      _dirty = true;
    } else {
      onCommit();
    }
  }
}