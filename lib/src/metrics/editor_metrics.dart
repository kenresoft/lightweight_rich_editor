import '../core/editor_document.dart';
import '../history/history_manager.dart';

/// Lightweight, read-only diagnostics about an editing session — useful
/// for a debug overlay, logging, or a size heuristic.
class EditorMetrics {
  final EditorDocument document;
  final HistoryManager history;

  const EditorMetrics({required this.document, required this.history});

  int get characterCount => document.length;

  /// A simple whitespace-run count, not a linguistically precise
  /// tokenizer (scripts with no spaces, e.g. CJK, aren't handled).
  int get wordCount {
    final trimmed = document.text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  int get attributeCount => document.attributeStore.length;

  int get undoDepth => history.undoDepth;

  int get redoDepth => history.redoDepth;

  @override
  String toString() =>
      'EditorMetrics(chars: $characterCount, words: $wordCount, spans: $attributeCount, '
          'undo: $undoDepth, redo: $redoDepth)';
}