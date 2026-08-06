/// Abstraction over the raw character storage backing an
/// [EditorDocument].
///
/// The [EditingEngine] (Phase 2) talks to text storage only through this
/// interface — never through a raw `String` directly. That indirection is
/// the entire point: [StringTextBuffer] is a correct, simple starting
/// implementation, and per the product brief we do **not** optimize this
/// prematurely. If document sizes ever demand it, a rope or piece-table
/// implementation can replace [StringTextBuffer] later without touching
/// the editing engine, renderer, or controller at all.
abstract class TextBuffer {
  int get length;

  String get text;

  bool get isEmpty;

  /// Returns the substring `[start, end)`. `end` defaults to [length].
  String substring(int start, [int? end]);

  /// Inserts `text` at `index`, shifting everything after it forward.
  void insert(int index, String text);

  /// Removes the characters in `[start, end)`.
  void delete(int start, int end);

  /// Replaces `[start, end)` with `text` in one step.
  void replace(int start, int end, String text);

  void clear();
}

/// A [TextBuffer] backed by a plain Dart [String].
///
/// Every operation is O(n) in document length, same as the controller it
/// replaces — this is a direct, unoptimized port of the existing
/// behavior, not a performance regression. It exists as the seam for a
/// future O(log n) implementation, not as one itself.
class StringTextBuffer implements TextBuffer {
  String _text;

  StringTextBuffer([String initial = '']) : _text = initial;

  @override
  int get length => _text.length;

  @override
  String get text => _text;

  @override
  bool get isEmpty => _text.isEmpty;

  @override
  String substring(int start, [int? end]) => _text.substring(start, end);

  @override
  void insert(int index, String text) {
    if (text.isEmpty) return;
    _text = _text.replaceRange(index, index, text);
  }

  @override
  void delete(int start, int end) {
    if (end <= start) return;
    _text = _text.replaceRange(start, end, '');
  }

  @override
  void replace(int start, int end, String text) {
    _text = _text.replaceRange(start, end, text);
  }

  @override
  void clear() => _text = '';

  @override
  String toString() => _text;
}