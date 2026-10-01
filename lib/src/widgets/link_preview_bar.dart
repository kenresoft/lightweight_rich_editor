import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A compact floating card showing the link the caret is in, with Copy, Open
/// and Close actions. The host decides when it appears (see the editor's link
/// bar host): only for a link the user just touched, never merely because a
/// note opened with its caret inside one.
///
/// Deliberately **tap-triggered, not hover-triggered** and **not caret-anchored**
/// (a bubble tracking the caret needs `TextField` internals that are not
/// public): a fixed bar is a smaller, safer surface for the same information.
class LinkPreviewBar extends StatelessWidget {
  const LinkPreviewBar({
    super.key,
    required this.url,
    required this.onOpen,
    this.onClose,
  });

  final String url;
  final VoidCallback onOpen;
  final VoidCallback? onClose;

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
    final (host, rest) = split(url);
    final isMail = url.startsWith('mailto:') || url.startsWith('tel:');
    final label = isMail
        ? url.replaceFirst(RegExp(r'^(mailto|tel):'), '')
        : host;
    return LayoutBuilder(
      builder: (context, box) {
        // Narrow hosts keep only what matters: the link and Open.
        final roomy = box.maxWidth >= 260;
        return _card(context, scheme, label, rest, isMail, roomy);
      },
    );
  }

  Widget _card(
    BuildContext context,
    ColorScheme scheme,
    String label,
    String rest,
    bool isMail,
    bool roomy,
  ) {
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(
          children: [
            Icon(
              isMail ? Icons.alternate_email_rounded : Icons.link_rounded,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rest.isNotEmpty)
                      TextSpan(
                        text: rest,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            if (roomy)
              IconButton(
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text('Link copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            IconButton(
              tooltip: 'Open link',
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: onOpen,
            ),
            if (onClose != null && roomy)
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}
