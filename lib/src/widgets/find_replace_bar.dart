import 'package:flutter/material.dart';

import '../controller/rich_editor_controller.dart';

/// A find/replace bar wired to [RichEditorController.search].
///
/// Manages its own local state (query text, replacement text, case/
/// whole-word toggles) via plain [setState] after each operation — it
/// does *not* wrap itself in a `ListenableBuilder(listenable: controller)`.
/// `SearchIndex` isn't a `Listenable` at all, and this widget owns every
/// interaction that changes search state (the query field's `onChanged`,
/// the next/previous/replace buttons), so there's no reactive gap to
/// bridge; every place that changes something already knows to
/// `setState`. This also sidesteps the exact anti-pattern that caused
/// the selection-drag bug earlier in this library's development —
/// though it wouldn't have applied here anyway, since this widget's own
/// `TextField` (the search query input) is a separate, independent
/// `TextEditingController`, not [controller] itself.
class FindReplaceBar extends StatefulWidget {
  final RichEditorController controller;

  /// Called when the user dismisses the bar. Typically sets a `bool`
  /// that conditionally includes this widget in the parent's tree —
  /// see the class-level example.
  final VoidCallback? onClose;

  /// Whether the replace row starts expanded.
  final bool showReplaceInitially;

  const FindReplaceBar({
    super.key,
    required this.controller,
    this.onClose,
    this.showReplaceInitially = false,
  });

  @override
  State<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends State<FindReplaceBar> {
  final _queryController = TextEditingController();
  final _replacementController = TextEditingController();
  final _queryFocusNode = FocusNode();

  late bool _showReplace = widget.showReplaceInitially;
  bool _caseSensitive = false;
  bool _wholeWord = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queryFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _replacementController.dispose();
    _queryFocusNode.dispose();
    // Ending the search when the bar goes away avoids leaving a stale
    // match selected in the editor after the bar that showed it is gone.
    widget.controller.clearFind();
    super.dispose();
  }

  void _runSearch(String query) {
    widget.controller.find(query, caseSensitive: _caseSensitive, wholeWord: _wholeWord);
    setState(() {});
  }

  void _next() {
    widget.controller.findNext();
    setState(() {});
  }

  void _previous() {
    widget.controller.findPrevious();
    setState(() {});
  }

  void _replaceCurrent() {
    widget.controller.replaceCurrentMatch(_replacementController.text);
    setState(() {});
  }

  void _replaceAll() {
    widget.controller.replaceAllMatches(_replacementController.text);
    setState(() {});
  }

  void _close() {
    widget.controller.clearFind();
    widget.controller.focusNode.requestFocus();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final search = widget.controller.search;
    final hasQuery = search.query.isNotEmpty;
    final noResults = hasQuery && search.matchCount == 0;
    final matchLabel = !hasQuery
        ? ''
        : noResults
        ? 'No results'
        : '${search.currentIndex + 1} of ${search.matchCount}';

    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(_showReplace ? Icons.expand_less : Icons.expand_more),
                  tooltip: _showReplace ? 'Hide replace' : 'Show replace',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showReplace = !_showReplace),
                ),
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    focusNode: _queryFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Find',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onChanged: _runSearch,
                    onSubmitted: (_) => _next(),
                  ),
                ),
                if (hasQuery)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      matchLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: noResults ? Theme.of(context).colorScheme.error : Colors.grey[600],
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Previous match',
                  visualDensity: VisualDensity.compact,
                  onPressed: search.matchCount > 0 ? _previous : null,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Next match',
                  visualDensity: VisualDensity.compact,
                  onPressed: search.matchCount > 0 ? _next : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: _close,
                ),
              ],
            ),
            if (_showReplace)
              Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: TextField(
                      controller: _replacementController,
                      decoration: const InputDecoration(
                        hintText: 'Replace',
                        isDense: true,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: search.matchCount > 0 ? _replaceCurrent : null,
                    child: const Text('Replace'),
                  ),
                  TextButton(
                    onPressed: search.matchCount > 0 ? _replaceAll : null,
                    child: const Text('Replace All'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 2),
              child: Row(
                children: [
                  _ToggleChip(
                    label: 'Aa',
                    tooltip: 'Case sensitive',
                    selected: _caseSensitive,
                    onChanged: (value) {
                      setState(() => _caseSensitive = value);
                      _runSearch(_queryController.text);
                    },
                  ),
                  const SizedBox(width: 6),
                  _ToggleChip(
                    label: 'Word',
                    tooltip: 'Whole word',
                    selected: _wholeWord,
                    onChanged: (value) {
                      setState(() => _wholeWord = value);
                      _runSearch(_queryController.text);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _ToggleChip({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: onChanged,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}