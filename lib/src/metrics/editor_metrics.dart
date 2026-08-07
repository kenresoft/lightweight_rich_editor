import '../core/editor_document.dart';
import '../history/history_manager.dart';

/// Lightweight, read-only diagnostics about an editing session.
///
/// These are developer tools — for a debug overlay, logging, or a
/// "is this note getting too big" heuristic — not something end users
/// see. Deliberately minimal: character/attribute counts and undo/redo
/// depth are essentially free (they read counters other components
/// already maintain). Render-timing metrics were considered and left
/// out — they'd need instrumentation threading through
/// `TextSpanRenderer` for a benefit that's speculative until something
/// is actually observed to be slow.
class EditorMetrics {
  final EditorDocument document;
  final HistoryManager history;

  const EditorMetrics({required this.document, required this.history});

  int get characterCount => document.length;

  /// A simple whitespace-run count — good enough for a live word-count
  /// display, not a linguistically precise tokenizer (it won't handle
  /// every script's notion of a "word" correctly, e.g. Chinese/Japanese
  /// text with no spaces). Fine for the common case; worth revisiting
  /// with a real segmenter if that ever matters for this app.
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