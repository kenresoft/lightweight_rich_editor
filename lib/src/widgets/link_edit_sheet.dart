import 'package:flutter/material.dart';

import '../utils/link_launcher.dart';
import '../utils/url_detector.dart';

/// The outcome of the link edit sheet: new visible [text] and [url], or
/// [remove] to unlink and keep the text.
class LinkEditResult {
  const LinkEditResult({required this.text, required this.url, this.remove = false});

  final String text;
  final String? url;
  final bool remove;
}

/// The address to store for what a user typed in the URL field: a bare domain
/// gets `https://`, an email address `mailto:`, an allowed scheme is kept;
/// `null` when it is not something a link can open.
String? hrefForInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final detected = normalizeUrlToken(text);
  if (detected != null) return detected;
  final uri = normalizeLinkUri(text);
  if (uri == null) return null;
  return uri.hasScheme && text.toLowerCase().startsWith('${uri.scheme}:') ? text : uri.toString();
}

/// A bottom sheet to edit a link's text and address, or remove the link.
Future<LinkEditResult?> showLinkEditSheet(
  BuildContext context, {
  required String text,
  required String url,
}) {
  return showModalBottomSheet<LinkEditResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _LinkEditSheet(text: text, url: url),
  );
}

class _LinkEditSheet extends StatefulWidget {
  const _LinkEditSheet({required this.text, required this.url});

  final String text;
  final String url;

  @override
  State<_LinkEditSheet> createState() => _LinkEditSheetState();
}

class _LinkEditSheetState extends State<_LinkEditSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.text);
  late final TextEditingController _url = TextEditingController(text: widget.url);
  String? _urlError;

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final href = hrefForInput(_url.text);
    if (href == null) {
      setState(() => _urlError = "That isn't a link we can open");
      return;
    }
    final text = _text.text.isEmpty ? _url.text.trim() : _text.text;
    Navigator.pop(context, LinkEditResult(text: text, url: href));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit link', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Text',
              prefixIcon: Icon(Icons.title_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Link',
              prefixIcon: const Icon(Icons.link_rounded),
              border: const OutlineInputBorder(),
              errorText: _urlError,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context, LinkEditResult(text: _text.text, url: null, remove: true)),
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Remove link'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
