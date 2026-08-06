import '../core/editor_document.dart';
import 'document_renderer.dart';

/// Renders a document down to its bare text, with formatting stripped.
///
/// This exists as much to *prove* the renderer seam works — that adding
/// an output format is a new small class, not a change to
/// `EditingEngine` or `AttributeStore` — as it is to be useful. It also
/// happens to be genuinely useful: note-list previews, search-result
/// snippets, and notification text all want plain content, not spans.
class PlainTextRenderer implements DocumentRenderer<String> {
  const PlainTextRenderer();

  @override
  String render(EditorDocument document) => document.text;

  /// [render], truncated to `maxLength` characters (adding an ellipsis
  /// if truncated), collapsing runs of whitespace/newlines into single
  /// spaces — the shape a one-line list preview actually wants.
  String renderPreview(EditorDocument document, {int maxLength = 140}) {
    final collapsed = document.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength).trimRight()}…';
  }
}