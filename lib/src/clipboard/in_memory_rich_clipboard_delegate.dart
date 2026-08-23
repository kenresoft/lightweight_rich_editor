import '../models/text_attribute.dart';
import 'rich_clipboard_delegate.dart';

/// A simple in-memory implementation of [RichClipboardDelegate].
/// Useful for internal copy/paste within the same app session.
class InMemoryRichClipboardDelegate implements RichClipboardDelegate {
  /// The default delegate every [RichEditorController] uses unless the
  /// host supplies its own. Shared (not per-controller) so copy/paste
  /// between controllers works the way a single system clipboard does;
  /// pass a custom `richClipboardDelegate` for per-controller isolation.
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
