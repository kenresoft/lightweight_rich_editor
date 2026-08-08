import 'package:flutter/material.dart';

/// Reusable link-entry form body, shared between [showLinkEntryDialog]
/// and [showLinkEntryBottomSheet] so both presentations stay visually
/// and behaviorally consistent instead of duplicating a TextField +
/// submit/cancel row in two places.
///
/// Deliberately does not call `RichEditorController.setLink()` itself —
/// it only resolves to a URL string via [onSubmit], or signals
/// cancellation via [onCancel]. That keeps it decoupled from the
/// controller, so it stays reusable anywhere a "get a URL from the
/// user" form is needed, not just from the link toolbar button.
class LinkEntryForm extends StatefulWidget {
  const LinkEntryForm({
    super.key,
    this.initialUrl,
    required this.onSubmit,
    required this.onCancel,
  });

  /// Pre-fills the field. Pass the currently active link — e.g.
  /// `controller.activeAttributeValue(AttributeType.link) as String?`
  /// — when editing a link already applied at the selection, rather
  /// than inserting a new one.
  final String? initialUrl;

  /// Called with a non-empty, trimmed URL on confirm.
  final ValueChanged<String> onSubmit;

  /// Called when the user explicitly cancels (Cancel button). Barrier/
  /// swipe dismissal is handled by the presenter functions below, not
  /// this callback.
  final VoidCallback onCancel;

  @override
  State<LinkEntryForm> createState() => _LinkEntryFormState();
}

class _LinkEntryFormState extends State<LinkEntryForm> {
  late final TextEditingController _urlController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorText = 'Enter a URL');
      return;
    }
    // Sensible default rather than a hard validation error: a bare
    // "example.com" is a perfectly normal thing to type here, so we
    // fill in a scheme instead of rejecting it. Anything that already
    // has a scheme (http://, mailto:, custom schemes, ...) passes
    // through untouched.
    final url = input.contains('://') ? input : 'https://$input';
    widget.onSubmit(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _urlController,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'https://example.com',
            errorText: _errorText,
          ),
          onChanged: (_) {
            if (_errorText != null) setState(() => _errorText = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            TextButton(onPressed: _submit, child: const Text('Insert')),
          ],
        ),
      ],
    );
  }
}

/// Shows [LinkEntryForm] in an [AlertDialog] — matches the styling the
/// old inline `_showLinkDialog` used. Resolves to the entered URL, or
/// `null` if the user cancelled or dismissed the dialog without one.
Future<String?> showLinkEntryDialog(BuildContext context, {String? initialUrl}) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Insert Link'),
      content: LinkEntryForm(
        initialUrl: initialUrl,
        onSubmit: (url) => Navigator.pop(context, url),
        onCancel: () => Navigator.pop(context),
      ),
    ),
  );
}

/// Same form, presented as a modal bottom sheet instead — useful on
/// narrower/touch-first layouts. Same return contract as
/// [showLinkEntryDialog]: entered URL, or `null` on cancel/dismiss.
/// Not wired up anywhere by default — swap this in for
/// [showLinkEntryDialog] at the call site if/when it's wanted.
Future<String?> showLinkEntryBottomSheet(BuildContext context, {String? initialUrl}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        top: false,
        child: LinkEntryForm(
          initialUrl: initialUrl,
          onSubmit: (url) => Navigator.pop(context, url),
          onCancel: () => Navigator.pop(context),
        ),
      ),
    ),
  );
}