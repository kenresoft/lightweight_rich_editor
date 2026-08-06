import '../core/editor_document.dart';

/// The minimal contract every renderer implements: turn an
/// [EditorDocument] into some output representation `T`.
///
/// This is deliberately thin. A `TextSpanRenderer` needs extra
/// Flutter-specific inputs — a base [TextStyle], an IME composing range —
/// that a hypothetical `MarkdownRenderer` or `PlainTextRenderer` simply
/// has no concept of, so this interface doesn't try to anticipate them.
/// Renderers are free to expose a richer method for their own callers
/// (see `TextSpanRenderer.renderSpan`) while still satisfying [render]
/// for callers that just want "the output, plainly" — an export path, a
/// search-result snippet, a notification preview.
abstract class DocumentRenderer<T> {
  T render(EditorDocument document);
}