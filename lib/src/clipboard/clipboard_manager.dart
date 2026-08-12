import '../commands/command_dispatcher.dart';
import '../core/editor_document.dart';
import '../core/editor_selection.dart';
import '../export/html_exporter.dart';
import '../import/html_importer.dart';
import '../import/markdown_importer.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/url_detector.dart';
import 'native/rich_clipboard_platform.dart';
import 'rich_clipboard_delegate.dart';

/// Copy/cut/paste for an [EditorDocument], via [CommandDispatcher] so
/// cut and paste are ordinary undoable edits like everything else.
///
/// This uses an internal native plugin to access rich content flavors
/// (like HTML) that browsers and other apps provide, which Flutter's
/// built-in `Clipboard` API cannot reach.
class ClipboardManager {
  final EditorDocument document;
  final CommandDispatcher commands;

  /// Optional backend for preserving formatting across copy/paste. See
  /// [RichClipboardDelegate] — copy/paste works as plain text without
  /// one.
  RichClipboardDelegate? delegate;

  ClipboardManager({required this.document, required this.commands, this.delegate});

  /// Copies `selection` to the system clipboard (plain text) and, if a
  /// [delegate] is set, to it as well (with formatting). No-op on a
  /// collapsed selection — there's nothing to copy.
  ///
  /// Reads from [EditorDocument.exportAttributes] rather than
  /// `document.attributeStore.findIntersecting(...)` directly — header
  /// formatting is read from `document.paragraphs` now (Phase 3 of the
  /// block-architecture migration), and `exportAttributes` is what
  /// synthesizes that back into the flat span list this method already
  /// clips and translates to selection-relative offsets. Without this,
  /// copying a heading would silently lose its header formatting the
  /// moment `AttributeStore`'s own header spans stopped being the read
  /// source elsewhere.
  Future<void> copy(EditorSelection selection) async {
    if (selection.isCollapsed) return;

    final text = document.text.substring(selection.start, selection.end);
    final attributes = document
        .exportAttributes()
        .where((attr) => attr.intersects(selection.start, selection.end))
        .map((attr) {
      final clippedStart = attr.start < selection.start ? selection.start : attr.start;
      final clippedEnd = attr.end > selection.end ? selection.end : attr.end;
      return attr.copyWith(
        start: clippedStart - selection.start,
        end: clippedEnd - selection.start,
      );
    })
        .toList(growable: false);

    delegate?.store(text, attributes);

    // Generate HTML to preserve formatting in the system clipboard.
    final html = const HtmlExporter().export(text, attributes);
    await RichClipboardPlatform.setData(text: text, html: html);
  }

  /// Copies `selection`, then deletes it. Returns the resulting
  /// selection (caret where the cut content used to start).
  Future<EditorSelection> cut(EditorSelection selection) async {
    await copy(selection);
    return commands.deleteSelection(selection);
  }

  /// Pastes at `selection`, preferring rich content from [delegate] when
  /// its stored plain text matches what's currently on the system
  /// clipboard (i.e. it's still the same copy, not something copied
  /// elsewhere since) — otherwise falls back to the HTML flavor if
  /// available via native plugin, or heuristic Markdown detection.
  ///
  /// Returns the resulting selection, or `null` if the clipboard had no
  /// content to paste.
  Future<EditorSelection?> paste(EditorSelection selection) async {
    // RichClipboardPlatform.getData() provides both plain text and HTML
    // from the system clipboard using native code.
    final data = await RichClipboardPlatform.getData();
    final plainText = data.text;
    final htmlText = data.html;

    if ((plainText == null || plainText.isEmpty) && (htmlText == null || htmlText.isEmpty)) {
      return null;
    }

    // Normalized purely for comparison, never for what actually gets
    // pasted: `rich.text` comes from our own in-memory delegate,
    // untouched by the OS — it's `plainText` (round-tripped through the
    // real system clipboard) that some platforms may have normalized
    // '\n' to '\r\n' on the way. Comparing raw could spuriously miss an
    // exact, same-session copy that should have taken the rich path,
    // falling through to a plain-text paste — losing formatting despite
    // the correct data still being right there in `rich`. Never
    // normalizing what's actually inserted matters: stripping '\r'
    // characters from text whose attributes were computed against its
    // original length would shift every offset after the strip point.
    final normalizedPlainText = plainText?.replaceAll('\r\n', '\n');

    final rich = delegate?.read();
    if (rich != null && rich.text == normalizedPlainText) {
      return commands.pasteRich(selection, rich.text, rich.attributes);
    }

    // 1. Try HTML if the clipboard provided it (e.g. copied from a browser)
    if (htmlText != null && htmlText.isNotEmpty) {
      final parsed = const HtmlImporter().parse(htmlText);
      // Only use the rich import if it actually found formatting or
      // meaningful structure.
      if (parsed.attributes.isNotEmpty || (normalizedPlainText != null && parsed.text != normalizedPlainText)) {
        return commands.pasteRich(selection, parsed.text, parsed.attributes);
      }
    }

    // 2. Fallback to heuristic Markdown detection on the plain text version
    if (plainText != null && plainText.isNotEmpty) {
      if (_looksLikeMarkdown(plainText)) {
        final parsed = const MarkdownImporter().parse(plainText);
        if (parsed.attributes.isNotEmpty) {
          return commands.pasteRich(selection, parsed.text, parsed.attributes);
        }
      }

      // 3. Final fallback: plain text with autolink detection
      final urls = detectAllUrls(plainText);
      if (urls.isNotEmpty) {
        final attributes = urls.map((u) => TextAttribute(
          start: u.start,
          end: u.end,
          type: AttributeType.link,
          value: u.href,
        )).toList();
        return commands.pasteRich(selection, plainText, attributes);
      }

      return commands.paste(selection, plainText);
    }

    return null;
  }

  bool _looksLikeMarkdown(String text) {
    // Detects common Markdown markers.
    // 1. Headers: # at start of line
    if (RegExp(r'^#+ ', multiLine: true).hasMatch(text)) {
      return true;
    }

    // 2. Inline markers: bold, strikethrough, code
    if (text.contains('**') || text.contains('__') ||
        text.contains('~~') || text.contains('`')) {
      return true;
    }

    // 3. Italic markers: single * or _ with content
    if (RegExp(r'([*_]).+\1').hasMatch(text)) {
      return true;
    }

    // 4. Links: [text](url)
    if (RegExp(r'\[.*\]\(.*\)').hasMatch(text)) {
      return true;
    }

    return false;
  }
}