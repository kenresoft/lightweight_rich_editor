import '../models/text_attribute.dart';

/// A pluggable backend for *rich* (formatted) copy/paste.
///
/// [ClipboardManager] always copies/pastes plain text through Flutter's
/// system clipboard — that works everywhere, with no setup. Preserving
/// *formatting* across a copy/paste needs somewhere to stash the spans
/// too (the system clipboard is plain-text-only for our purposes), and
/// where that "somewhere" lives is app-specific — in-memory, a
/// platform channel to a native rich-clipboard API, shared_preferences,
/// whatever. Implement this to plug your app's own storage in, so the
/// library never hard-depends on one app's specific clipboard class.
///
/// Without a delegate, copy/paste still works correctly — just as plain
/// text, same as pasting into any editor from a source that doesn't
/// preserve formatting.
abstract class RichClipboardDelegate {
  /// Stores `text` and its `attributes` (relative to the start of
  /// `text`) for a subsequent [read].
  void store(String text, List<TextAttribute> attributes);

  /// Returns the most recently [store]d content, or `null` if nothing's
  /// been stored (or the delegate doesn't have anything relevant right
  /// now — e.g. the system clipboard was overwritten by another app
  /// since the last copy).
  ({String text, List<TextAttribute> attributes})? read();
}