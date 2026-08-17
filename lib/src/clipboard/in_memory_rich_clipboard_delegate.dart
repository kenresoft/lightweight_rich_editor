import '../models/text_attribute.dart';
import 'rich_clipboard_delegate.dart';

/// A simple in-memory implementation of [RichClipboardDelegate].
/// Useful for internal copy/paste within the same app session.
///
/// [RichEditorController] defaults to [shared] rather than a fresh
/// instance per controller — a real, reported bug: a fresh
/// `InMemoryRichClipboardDelegate()` per controller means every
/// controller has its *own* private store, invisible to every other
/// one. That's silently wrong the moment an app has more than one
/// controller alive at a time (any multi-note app, opening a second note
/// while the first still exists, or even just recreating a controller
/// when navigating back to a note) — copying formatted text in one note
/// and pasting into another falls straight through to the OS-clipboard
/// HTML fallback instead of the always-reliable delegate path, and for
/// content that never leaves the app in the first place (nothing else
/// on the system clipboard would ever produce this exact plain-text
/// match), that fallback can end up landing as plain text: exactly the
/// "internal paste loses formatting" complaint this fixes. A single
/// shared store makes "copy here, paste there" behave the way every
/// other app on the platform already does — the system clipboard has
/// exactly one slot, not one per open document. An app that genuinely
/// wants per-controller isolation can still opt out by passing its own
/// `richClipboardDelegate` explicitly.
class InMemoryRichClipboardDelegate implements RichClipboardDelegate {
  /// The default delegate every [RichEditorController] uses unless the
  /// host supplies its own — see the class doc comment for why a shared
  /// instance, not a fresh one per controller, is the correct default.
  static final InMemoryRichClipboardDelegate shared = InMemoryRichClipboardDelegate();

  String? _text;
  List<TextAttribute>? _attributes;

  @override
  void store(String text, List<TextAttribute> attributes) {
    _text = text;
    _attributes = attributes;
  }

  @override
  ({String text, List<TextAttribute> attributes})? read() {
    if (_text == null || _attributes == null) return null;
    return (text: _text!, attributes: _attributes!);
  }
}
