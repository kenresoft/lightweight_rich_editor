import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/link_launcher.dart';

/// A compact floating card showing the link the caret is in, with Open, Copy,
/// Edit and Remove actions. The host decides when it appears (see the editor's
/// link bar host): only for a link the user just touched, never because a note
/// opened or text was pasted with the caret inside one.
///
/// Deliberately **tap-triggered, not hover-triggered** and **not caret-anchored**
/// (a bubble tracking the caret needs `TextField` internals that are not
/// public): a fixed bar is a smaller, safer surface for the same information.
class LinkPreviewBar extends StatelessWidget {
  const LinkPreviewBar({
    super.key,
    required this.url,
    required this.onOpen,
    this.onEdit,
    this.onRemove,
  });

  final String url;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  /// "https://docs.kenresoft.com/cms/" -> ("docs.kenresoft.com", "/cms/")
  static (String host, String rest) split(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return (url, '');
    var rest = uri.path;
    if (uri.hasQuery) rest += '?${uri.query}';
    if (rest == '/') rest = '';
    return (uri.host.replaceFirst(RegExp(r'^www\.'), ''), rest);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = normalizeLinkUri(url);
    final isMail = target?.scheme == 'mailto';
    final isTel = target?.scheme == 'tel';
    final (host, rest) = (isMail || isTel) ? (linkDisplayTarget(url), '') : split(url);
    return LayoutBuilder(
      builder: (context, box) {
        // Narrow hosts keep only what matters: the link and Open.
        final roomy = box.maxWidth >= 300;
        return Material(
          color: scheme.surfaceContainerHigh,
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Icon(
                  isMail
                      ? Icons.alternate_email_rounded
                      : isTel
                      ? Icons.call_rounded
                      : Icons.link_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: host, style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600)),
                        if (rest.isNotEmpty) TextSpan(text: rest, style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                _action(Icons.open_in_new_rounded, 'Open link', onOpen),
                if (roomy)
                  _action(Icons.copy_rounded, 'Copy link', () {
                    Clipboard.setData(ClipboardData(text: linkDisplayTarget(url)));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 1)),
                    );
                  }),
                if (roomy && onEdit != null) _action(Icons.edit_outlined, 'Edit link', onEdit!),
                if (roomy && onRemove != null) _action(Icons.link_off_rounded, 'Remove link', onRemove!),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _action(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
