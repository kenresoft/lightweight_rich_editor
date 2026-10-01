import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _emailPattern = RegExp(r'^[^\s@/:]+@[^\s@/:]+\.[^\s@/:]+$');
final RegExp _hostPattern = RegExp(r'^(www\.)?[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+([/?#:].*)?$');

/// Schemes a note link may open. Anything else (`javascript:`, `file:`,
/// `intent:`, custom app schemes) is refused rather than handed to the OS.
const Set<String> _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

/// The [Uri] a link's stored text should open, or `null` if it is not a link
/// worth opening.
///
/// A scheme-less `example.com/page` or `www.example.com` opens as `https://`;
/// a bare `name@host.tld` opens as `mailto:`. Only [_allowedSchemes] are
/// accepted; blank text, text with spaces and other schemes yield `null`.
Uri? normalizeLinkUri(String raw) {
  final text = raw.trim();
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;

  final parsed = Uri.tryParse(text);
  if (parsed != null && parsed.hasScheme) {
    // `host:80` parses with "host" as the scheme; accept only real schemes.
    if (!_allowedSchemes.contains(parsed.scheme.toLowerCase())) {
      return _hostPattern.hasMatch(text) ? Uri.tryParse('https://$text') : null;
    }
    if ((parsed.scheme == 'http' || parsed.scheme == 'https') && parsed.host.isEmpty) return null;
    return parsed;
  }
  if (_emailPattern.hasMatch(text)) return Uri.tryParse('mailto:$text');
  if (_hostPattern.hasMatch(text)) return Uri.tryParse('https://$text');
  return null;
}

/// Default handler for [RichEditorController]'s `onTapLink` — opens
/// [url] via the platform's external-browser mechanism. Used directly
/// when `RichTextEditor.confirmBeforeOpeningLinks` is `false`;
/// otherwise [confirmAndLaunchLink] wraps this.
///
/// Returns whether a handler was launched. Invalid or unlaunchable URLs are
/// swallowed (`false`) rather than thrown — a stray tap on a broken link
/// should never crash the editor.
Future<bool> launchLinkUrl(String url) async {
  final uri = normalizeLinkUri(url);
  if (uri == null) return false;

  try {
    // Deliberately no `canLaunchUrl` pre-check: on Android 11+ it only reports
    // true for schemes the app declared in its manifest `<queries>`, so an app
    // that had not declared http/https silently refused every link. `launchUrl`
    // itself needs no declaration and returns false when nothing can handle it.
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Shows an "Open link?" confirmation before calling [launchLinkUrl] —
/// guards against opening a link from an accidental tap, since tapping
/// inside editable rich text is also how the caret is moved near a link.
/// If the link then cannot be opened, says so in a snackbar.
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

  if (shouldOpen != true) return;
  final opened = await launchLinkUrl(url);
  if (!opened && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("Couldn't open this link")),
    );
  }
}
