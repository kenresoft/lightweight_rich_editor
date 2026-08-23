import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Default handler for [RichEditorController]'s `onTapLink` — opens
/// [url] via the platform's external-browser mechanism. Used directly
/// when `RichTextEditor.confirmBeforeOpeningLinks` is `false`;
/// otherwise [confirmAndLaunchLink] wraps this.
///
/// Invalid or unlaunchable URLs are swallowed rather than thrown — a
/// stray tap on a broken link should never crash the editor.
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

/// Shows an "Open link?" confirmation before calling [launchLinkUrl] —
/// guards against opening a link from an accidental tap, since tapping
/// inside editable rich text is also how the caret is moved near a link.
///
/// This is the default tap behavior `RichTextEditor` wires up when
/// `confirmBeforeOpeningLinks` is `true` (the default).
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