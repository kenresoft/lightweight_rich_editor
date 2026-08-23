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
  /// collapsed selection.
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
  /// clipboard (i.e. it's still the same copy) — otherwise falls back to
  /// the HTML flavor if available, or heuristic Markdown detection.
  ///
  /// Returns the resulting selection, or `null` if there was nothing to
  /// paste.
  Future<EditorSelection?> paste(EditorSelection selection) async {
    final data = await RichClipboardPlatform.getData();
    final plainText = data.text;
    final htmlText = data.html;

    if ((plainText == null || plainText.isEmpty) && (htmlText == null || htmlText.isEmpty)) {
      return null;
    }

    // The system clipboard (Windows especially) may normalize '\n' to
    // '\r\n'; isAutolinkBoundary doesn't recognize '\r', which broke
    // autolinking on multi-line pastes. Normalize once here and use
    // `normalizedPlainText` (not `plainText`) for every decision below.
    final normalizedPlainText = plainText?.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final rich = delegate?.read();
    if (rich != null && rich.text == normalizedPlainText) {
      return commands.pasteRich(selection, rich.text, rich.attributes);
    }

    // 1. HTML flavor, if the clipboard provided one.
    if (htmlText != null && htmlText.isNotEmpty) {
      final parsed = const HtmlImporter().parse(htmlText);
      if (parsed.attributes.isNotEmpty || (normalizedPlainText != null && parsed.text != normalizedPlainText)) {
        // _withAutolinks still runs here: a bare URL from e.g. a
        // browser address bar can arrive as unstyled HTML with no
        // anchor tag, so parsed.attributes alone wouldn't catch it.
        return commands.pasteRich(selection, parsed.text, _withAutolinks(parsed.text, parsed.attributes));
      }
    }

    // 2. Heuristic Markdown detection on the plain text.
    if (normalizedPlainText != null && normalizedPlainText.isNotEmpty) {
      final text = normalizedPlainText;
      if (_looksLikeMarkdown(text)) {
        final parsed = const MarkdownImporter().parse(text);
        if (parsed.attributes.isNotEmpty) {
          return commands.pasteRich(selection, parsed.text, _withAutolinks(parsed.text, parsed.attributes));
        }
      }

      // 3. Plain text with autolink detection.
      final withAutolinks = _withAutolinks(text, const []);
      if (withAutolinks.isNotEmpty) {
        return commands.pasteRich(selection, text, withAutolinks);
      }

      return commands.paste(selection, text);
    }

    return null;
  }

  // Adds a synthesized link attribute for every detected URL not already
  // covered by `attributes`, so bare URLs get linkified on every paste
  // path regardless of source (HTML, Markdown, or plain text).
  List<TextAttribute> _withAutolinks(String text, List<TextAttribute> attributes) {
    final urls = detectAllUrls(text);
    if (urls.isEmpty) return attributes;

    final autolinks = urls
        .where((u) => !attributes.any((a) => a.type == AttributeType.link && a.intersects(u.start, u.end)))
        .map((u) => TextAttribute(start: u.start, end: u.end, type: AttributeType.link, value: u.href));

    return autolinks.isEmpty ? attributes : [...attributes, ...autolinks];
  }

  bool _looksLikeMarkdown(String text) {
    if (RegExp(r'^#+ ', multiLine: true).hasMatch(text)) {
      return true;
    }

    if (text.contains('**') || text.contains('__') ||
        text.contains('~~') || text.contains('`')) {
      return true;
    }

    if (RegExp(r'([*_]).+\1').hasMatch(text)) {
      return true;
    }

    if (RegExp(r'\[.*\]\(.*\)').hasMatch(text)) {
      return true;
    }

    return false;
  }
}