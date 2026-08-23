import '../models/text_attribute.dart';

/// A pluggable backend for storing formatting across copy/paste.
///
/// The system clipboard only carries plain text, so [ClipboardManager]
/// uses this to stash spans alongside it. Without a delegate, copy/paste
/// still works, just as plain text.
abstract class RichClipboardDelegate {
  /// Stores `text` and its `attributes` (relative to the start of
  /// `text`) for a subsequent [read].
  void store(String text, List<TextAttribute> attributes);

  /// Returns the most recently [store]d content, or `null` if nothing's
  /// been stored.
  ({String text, List<TextAttribute> attributes})? read();
}