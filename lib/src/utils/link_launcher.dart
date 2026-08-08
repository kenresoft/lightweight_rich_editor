import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Default handler for [RichEditorController]'s `onTapLink` — opens
/// [url] via the platform's standard external-browser mechanism, with
/// no confirmation step. Used directly when
/// `RichTextEditor.confirmBeforeOpeningLinks` is `false`; otherwise
/// [confirmAndLaunchLink] wraps this.
///
/// Invalid or unlaunchable URLs (malformed text, no handler
/// registered, platform declines) are swallowed rather than thrown —
/// a stray tap on a broken link should never crash the editor.
Future<void> launchLinkUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  try {
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Swallowed — see doc comment above.
  }
}

/// Shows a lightweight "Open link?" confirmation before calling
/// [launchLinkUrl] — guards against a link being opened from an
/// accidental tap, which is a real risk here specifically because
/// tapping *inside* editable rich text is also the normal way to move
/// the caret near a link to edit it.
///
/// This is the default tap behavior `RichTextEditor` wires up (see
/// `RichTextEditor.confirmBeforeOpeningLinks`, which defaults to
/// `true`) for both manually-created and autolinked links alike —
/// this function has no idea which kind of link it was called for,
/// since both paths ultimately store the same `AttributeType.link`
/// attribute and both go through the same `renderer.onTapLink`.
///
/// Guards on `context.mounted` before showing the dialog: the
/// `BuildContext` here was captured by a `RichTextEditor.build()` call
/// and handed to a `TapGestureRecognizer` that may fire an arbitrary
/// amount of time later (whenever the user actually taps) — by which
/// point the widget could plausibly have been unmounted (e.g. the note
/// screen was popped a moment before the tap lands).
Future<void> confirmAndLaunchLink(BuildContext context, String url) async {
  if (!context.mounted) return;

  final shouldOpen = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Open link?'),
      content: Text(url),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Open'),
        ),
      ],
    ),
  );

  if (shouldOpen == true) {
    await launchLinkUrl(url);
  }
}