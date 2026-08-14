import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A compact, dismissible bar showing the URL of the link the caret is
/// currently inside, with "Open" and "Copy" actions.
///
/// Deliberately **tap-triggered, not hover-triggered**: this codebase has
/// no `MouseRegion`/hover concept anywhere (links live as `TextSpan`
/// segments inside one `TextField`'s rendered content, not separate
/// widgets a `MouseRegion` could wrap), and manual `RenderParagraph`
/// hit-testing on every pointer move to fake hover would be a much larger
/// feature than what this is actually solving — a lighter-weight
/// affordance than the long-press context menu (`RichTextEditor`'s
/// `contextMenuBuilder`), triggered by wherever the caret already is.
/// Also deliberately **not caret-anchored** — a floating bubble that
/// tracks the live caret position needs a `LayerLink`/
/// `CompositedTransformFollower` wired into `TextField` internals that
/// isn't exposed by the public widget; a fixed bar is a smaller, safer
/// surface for the same information.
class LinkPreviewBar extends StatelessWidget {
  const LinkPreviewBar({
    super.key,
    required this.url,
    required this.onOpen,
  });

  final String url;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          children: [
            Icon(Icons.link, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            ),
            IconButton(
              tooltip: 'Open link',
              icon: const Icon(Icons.open_in_new, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
