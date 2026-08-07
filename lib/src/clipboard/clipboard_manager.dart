import 'package:flutter/services.dart';

import '../commands/command_dispatcher.dart';
import '../core/editor_document.dart';
import '../core/editor_selection.dart';
import 'rich_clipboard_delegate.dart';

/// Copy/cut/paste for an [EditorDocument], via [CommandDispatcher] so
/// cut and paste are ordinary undoable edits like everything else.
///
/// This used to live as private methods inside the app's `RichTextEditor`
/// widget — functionally fine, but it meant clipboard behavior wasn't
/// reusable by any other UI built on the same controller, and it forced
/// the widget layer to reach into `document.attributes`/`document.text`
/// directly rather than going through the library's own API. Moving it
/// here means any widget wrapping [RichEditorController] — a plain
/// `TextField`, a custom canvas editor, a test — gets working copy/cut/
/// paste for free, and rich formatting round-trips through an optional
/// [RichClipboardDelegate] instead of a hard dependency on one app's
/// clipboard class.
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
  Future<void> copy(EditorSelection selection) async {
    if (selection.isCollapsed) return;

    final text = document.text.substring(selection.start, selection.end);
    final attributes = document.attributeStore
        .findIntersecting(selection.start, selection.end)
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
    await Clipboard.setData(ClipboardData(text: text));
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
  /// elsewhere since) — otherwise falls back to plain-text paste from
  /// the system clipboard. Returns the resulting selection, or `null` if
  /// the clipboard had no text to paste.
  Future<EditorSelection?> paste(EditorSelection selection) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final plainText = data?.text;
    if (plainText == null || plainText.isEmpty) return null;

    final rich = delegate?.read();
    if (rich != null && rich.text == plainText) {
      return commands.pasteRich(selection, rich.text, rich.attributes);
    }
    return commands.paste(selection, plainText);
  }
}