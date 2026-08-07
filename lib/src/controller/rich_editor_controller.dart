import 'package:flutter/material.dart';

import '../clipboard/clipboard_manager.dart';
import '../clipboard/rich_clipboard_delegate.dart';
import '../commands/command_dispatcher.dart';
import '../commands/replace_range_command.dart';
import '../core/editing_engine.dart';
import '../core/editor_document.dart';
import '../core/editor_selection.dart';
import '../core/transaction_manager.dart';
import '../history/history_manager.dart';
import '../metrics/editor_metrics.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../rendering/render_theme.dart';
import '../rendering/text_span_renderer.dart';
import '../search/search_index.dart';
import '../utils/clamp_int.dart';
import '../utils/text_diff.dart';

/// The public API of the editor: a [TextEditingController] that
/// coordinates [EditorDocument], [EditingEngine], [HistoryManager]/
/// [CommandDispatcher], [TextSpanRenderer], and [ClipboardManager].
///
/// This is deliberately thin — it does not implement editing logic,
/// span math, undo grouping, style resolution, or clipboard handling
/// itself. Every one of those lives in the component built for it.
/// What this class owns is the handful of things that only make sense
/// at the `TextField` boundary:
/// 1. Diffing `TextField`'s before/after whole-string reports into
///    [ReplaceRangeCommand]s (see the `set value` override).
/// 2. Converting between Flutter's [TextSelection] and the engine's
///    framework-agnostic [EditorSelection].
/// 3. Keeping [TextEditingController.value] in sync with [document] as
///    the single [TransactionManager] commit callback ([_handleCommit]).
///
/// Compare this to the original `RichTextEditingController`, which did
/// all of the above *and* every editing method *and* undo/redo *and*
/// `buildTextSpan` in one file.
class RichEditorController extends TextEditingController {
  final EditorDocument document;
  late final TransactionManager transactions;
  late final EditingEngine engine;
  late final HistoryManager history;
  late final CommandDispatcher commands;
  late final ClipboardManager clipboard;
  late final EditorMetrics metrics;
  late final SearchIndex search;
  final TextSpanRenderer renderer;

  final FocusNode focusNode;
  final bool _ownsFocusNode;

  RichEditorController({
    String text = '',
    List<TextAttribute> initialAttributes = const [],
    FocusNode? focusNode,
    RichTextRenderTheme theme = RichTextRenderTheme.standard,
    Duration typingTimeout = const Duration(milliseconds: 800),
    int maxHistoryLength = 500,
    RichClipboardDelegate? richClipboardDelegate,
    void Function(String url)? onTapLink,
  })  : document = EditorDocument.fromText(text, initialAttributes),
        renderer = TextSpanRenderer(theme: theme, onTapLink: onTapLink),
        focusNode = focusNode ?? FocusNode(),
        _ownsFocusNode = focusNode == null,
        super(text: text) {
    transactions = TransactionManager(_handleCommit);
    engine = EditingEngine(document: document, transactions: transactions);
    history = HistoryManager(
      engine: engine,
      typingTimeout: typingTimeout,
      maxHistoryLength: maxHistoryLength,
    );
    commands = CommandDispatcher(engine: engine, history: history);
    clipboard = ClipboardManager(document: document, commands: commands, delegate: richClipboardDelegate);
    metrics = EditorMetrics(document: document, history: history);
    search = SearchIndex(document: document, commands: commands);
    this.focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    // Reserved for future focus-driven behavior (e.g. committing a
    // pending IME composition on blur). No-op today, same as the
    // original controller.
  }

  @override
  void dispose() {
    focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) focusNode.dispose();
    renderer.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // TextField boundary
  // ---------------------------------------------------------------------

  /// Called by the framework whenever the `TextField` bound to this
  /// controller has a new value — every keystroke, autocorrect
  /// replacement, IME composition update, and selection change.
  ///
  /// This is the only place raw text-diffing happens. It figures out
  /// *what* changed via [diffText], turns that into one
  /// [ReplaceRangeCommand], and lets [HistoryManager] decide whether it
  /// coalesces with the in-progress typing session. Selection-only
  /// changes (arrow keys, taps) skip straight to syncing sticky
  /// formatting and breaking coalescing — no diffing needed since the
  /// text didn't change.
  @override
  set value(TextEditingValue newValue) {
    final oldText = document.text;
    final newText = newValue.text;

    if (oldText == newText) {
      if (newValue.selection != selection) {
        history.breakCoalescing();
        if (newValue.selection.isCollapsed) {
          engine.syncStickyAttributesAt(newValue.selection.start);
        }
      }
      super.value = newValue;
      return;
    }

    final cursorHint = selection.start >= 0 ? selection.start : null;
    final diff = diffText(oldText, newText, cursorHint: cursorHint);

    if (!diff.isNoOp) {
      history.execute(ReplaceRangeCommand(
        start: diff.start,
        end: diff.end,
        text: diff.insertedText,
        attributesForInsertion: Map.of(engine.stickyAttributes),
      ));
    }

    // Trust the TextField/IME's own reported selection for where the
    // caret actually lands — autocorrect and IME composition can put it
    // somewhere `diff` alone wouldn't predict.
    super.value = TextEditingValue(
      text: document.text,
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }

  /// Assigns `newValue`, guaranteeing listeners are notified even when
  /// `newValue == value`.
  ///
  /// `ValueNotifier.value`'s setter — which `TextEditingController`
  /// inherits — skips `notifyListeners()` when the new value equals the
  /// old one. That's the right optimization for `ValueNotifier` in
  /// general, but wrong here: `TextEditingValue` equality only covers
  /// text, selection, and composing range. It has no concept of
  /// formatting, which lives entirely in [document]'s `AttributeStore`.
  /// A pure formatting change (toggle bold, undo a formatting command)
  /// leaves text/selection/composing all unchanged, so it produces a
  /// `TextEditingValue` indistinguishable from the current one — and the
  /// inherited setter would silently swallow the notification, leaving
  /// the `TextField` showing stale styling until some *other*, genuinely
  /// value-changing edit forces a rebuild. Every call site that can
  /// possibly be a formatting-only change routes through this instead of
  /// `super.value =` directly.
  void _applyValue(TextEditingValue newValue) {
    final valueActuallyChanged = newValue != value;
    super.value = newValue;
    if (!valueActuallyChanged) {
      notifyListeners();
    }
  }

  /// The single [TransactionManager] commit callback — fires once per
  /// logical edit (however many engine calls it took) and keeps
  /// [TextEditingController.value]'s text in sync with [document].
  ///
  /// This clamps the *existing* selection to the new text length rather
  /// than computing where it should end up; that's correct for
  /// formatting-only changes (text length is unchanged, so the current
  /// selection is already right) but not for text-content changes
  /// (inserting/deleting moves the caret). Every call site that changes
  /// text content — [insertText], [deleteBackward]/[deleteForward],
  /// paste, undo/redo, and the `set value` override above — corrects the
  /// selection explicitly afterward via [_syncSelection]. The one
  /// accepted trade-off: those call sites end up notifying listeners
  /// twice (once from this guess, once from the correction) instead of
  /// once. Simpler and more robust than threading "what selection should
  /// this commit produce" through [TransactionManager], which has no
  /// business knowing that.
  void _handleCommit() {
    final newText = document.text;
    final length = newText.length;
    final clamped = TextSelection(
      baseOffset: clampInt(selection.baseOffset, 0, length),
      extentOffset: clampInt(selection.extentOffset, 0, length),
    );
    _applyValue(value.copyWith(
      text: newText,
      selection: clamped,
      composing: newText == value.text ? value.composing : TextRange.empty,
    ));
  }

  void _syncSelection(EditorSelection result) {
    _applyValue(value.copyWith(
      text: document.text,
      selection: _toTextSelection(result),
      composing: TextRange.empty,
    ));
  }

  /// The current selection as an [EditorSelection], defensively clamped.
  ///
  /// A freshly constructed `TextEditingController` starts with
  /// `selection = TextSelection.collapsed(offset: -1)` until the bound
  /// `TextField` is focused — Flutter's own sentinel for "no selection
  /// yet". Every programmatic editing method below (`insertText`,
  /// `toggleBold`, ...) reads this getter, so without this guard,
  /// calling one of them before the field is ever focused — entirely
  /// plausible for something like "insert a template into a new note" —
  /// would pass `-1` straight through to [EditingEngine.replaceRange]
  /// and trip its bounds assertion. Falling back to the end of the
  /// document is the same thing focusing an empty text field would do.
  EditorSelection get _currentSelection {
    if (selection.start < 0 || selection.end < 0) {
      return EditorSelection.collapsed(document.length);
    }
    return _toEditorSelection(selection);
  }

  TextSelection _toTextSelection(EditorSelection s) =>
      TextSelection(baseOffset: s.baseOffset, extentOffset: s.extentOffset);

  EditorSelection _toEditorSelection(TextSelection s) =>
      EditorSelection(baseOffset: s.baseOffset, extentOffset: s.extentOffset);

  // ---------------------------------------------------------------------
  // Editing API — thin wrappers over CommandDispatcher for programmatic
  // use (toolbar buttons, keyboard shortcuts). TextField-driven typing
  // goes through the `set value` override above instead.
  // ---------------------------------------------------------------------

  void insertText(String text) => _syncSelection(commands.insertText(_currentSelection, text));

  void deleteBackward() => _syncSelection(commands.deleteBackward(_currentSelection));

  void deleteForward() => _syncSelection(commands.deleteForward(_currentSelection));

  /// Deletes the current selection outright. No-op if the selection is
  /// collapsed. Prefer this over `deleteBackward()` at call sites (like
  /// cut) that mean "delete what's selected" — `deleteBackward` happens
  /// to fall back to the same behavior for a non-collapsed selection,
  /// but that's an implementation detail, not something a call site
  /// should rely on to read clearly.
  void deleteSelection() => _syncSelection(commands.deleteSelection(_currentSelection));

  void pasteText(String text) => _syncSelection(commands.paste(_currentSelection, text));

  void pasteRichText(String text, List<TextAttribute> relativeAttributes) =>
      _syncSelection(commands.pasteRich(_currentSelection, text, relativeAttributes));

  /// Copies the current selection to the system clipboard (and to
  /// [clipboard]'s delegate, if one is set, preserving formatting). See
  /// [ClipboardManager.copy].
  Future<void> copy() => clipboard.copy(_currentSelection);

  /// Copies then deletes the current selection. See [ClipboardManager.cut].
  Future<void> cut() async => _syncSelection(await clipboard.cut(_currentSelection));

  /// Pastes at the current selection — rich content if [clipboard] has a
  /// matching delegate entry, otherwise plain text from the system
  /// clipboard. See [ClipboardManager.paste].
  Future<void> paste() async {
    final result = await clipboard.paste(_currentSelection);
    if (result != null) _syncSelection(result);
  }

  void toggleBold() => commands.toggleBold(_currentSelection);
  void toggleItalic() => commands.toggleItalic(_currentSelection);
  void toggleUnderline() => commands.toggleUnderline(_currentSelection);
  void toggleStrikethrough() => commands.toggleStrikethrough(_currentSelection);
  void toggleHighlight() => commands.toggleHighlight(_currentSelection);
  void toggleCode() => commands.toggleCode(_currentSelection);

  void setColor(int? argb) => commands.setColor(_currentSelection, argb);
  void setSize(num? size) => commands.setSize(_currentSelection, size);
  void setLink(String? url) => commands.setLink(_currentSelection, url);
  void setHeader(String? level) => commands.setHeader(_currentSelection, level);

  void clearFormatting() => commands.clearFormatting(_currentSelection);

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  void undo() {
    final result = history.undo();
    if (result != null) _syncSelection(result);
  }

  void redo() {
    final result = history.redo();
    if (result != null) _syncSelection(result);
  }

  /// Whether `type` is active at the current selection — a collapsed
  /// caret checks pending sticky formatting and whatever's applied right
  /// at that position; a range checks whether a single span covers the
  /// whole selection. Drives toolbar button highlighted state.
  bool isAttributeActive(AttributeType type) {
    final sel = _currentSelection;
    if (sel.isCollapsed) {
      return engine.stickyAttributes.containsKey(type) ||
          document.attributeStore.findAt(sel.start, type: type).isNotEmpty;
    }
    return document.attributeStore.coversRange(sel.start, sel.end, type);
  }

  /// The active value of a value-carrying attribute (color, size, link,
  /// header) at the current selection, or `null` if not active /
  /// inconsistent across the selection. Drives toolbar value display
  /// (e.g. showing the current color swatch).
  Object? activeAttributeValue(AttributeType type) {
    final sel = _currentSelection;
    if (sel.isCollapsed) {
      if (engine.stickyAttributes.containsKey(type)) return engine.stickyAttributes[type];
      final at = document.attributeStore.findAt(sel.start, type: type);
      return at.isEmpty ? null : at.first.value;
    }
    final covering = document.attributeStore
        .findIntersecting(sel.start, sel.end, type: type)
        .where((s) => s.covers(sel.start, sel.end));
    return covering.isEmpty ? null : covering.first.value;
  }

  // ---------------------------------------------------------------------
  // Document load / export
  // ---------------------------------------------------------------------

  /// Replaces the entire document — used when opening a different note
  /// in the same controller/widget rather than constructing a new
  /// [RichEditorController]. Clears undo history, since undoing past a
  /// document swap doesn't mean anything.
  void loadDocument(String text, [List<TextAttribute> attributes = const []]) {
    document.reset(text, attributes);
    engine.restoreStickyAttributes(const {});
    history.clear();
    _applyValue(TextEditingValue(
      text: document.text,
      selection: const TextSelection.collapsed(offset: 0),
    ));
  }

  Map<String, dynamic> toJson() => document.toJson();

  // ---------------------------------------------------------------------
  // Find & replace
  // ---------------------------------------------------------------------

  /// Runs a new search and, if there's a match, selects it in the
  /// editor. See [SearchIndex.search].
  void find(String query, {bool caseSensitive = false, bool wholeWord = false}) {
    search.search(query, caseSensitive: caseSensitive, wholeWord: wholeWord);
    _selectCurrentMatch();
  }

  /// Selects the next match, wrapping around. No-op if there are none.
  void findNext() {
    search.next();
    _selectCurrentMatch();
  }

  /// Selects the previous match, wrapping around. No-op if there are none.
  void findPrevious() {
    search.previous();
    _selectCurrentMatch();
  }

  /// Replaces the current match and selects the next one, if any. See
  /// [SearchIndex.replaceCurrent].
  void replaceCurrentMatch(String replacement) {
    final result = search.replaceCurrent(replacement);
    if (result != null) {
      _syncSelection(result);
      _selectCurrentMatch();
    }
  }

  /// Replaces every current match, as one undoable edit. See
  /// [SearchIndex.replaceAll].
  int replaceAllMatches(String replacement) => search.replaceAll(replacement);

  /// Ends the current search and clears its match selection.
  ///
  /// Notifies unconditionally, even though nothing about
  /// [TextEditingController.value] changes — the current-match highlight
  /// (see [buildTextSpan]) is driven by `search.currentMatch`, not by
  /// `value`, specifically so it stays visible while a find bar has
  /// focus. That means clearing it needs its own explicit rebuild
  /// trigger; without this, a highlighted match would visibly linger on
  /// screen after the find bar closes.
  void clearFind() {
    search.clear();
    notifyListeners();
  }

  void _selectCurrentMatch() {
    final match = search.currentMatch;
    if (match == null) {
      // No match (e.g. a query with zero results) — still notify, or a
      // *previous* search's highlight would stay visibly stuck on
      // screen. Same reasoning as clearFind above: the highlight isn't
      // driven by `value`, so a `value`-only change check can't be
      // trusted to catch this.
      notifyListeners();
      return;
    }
    _applyValue(value.copyWith(
      selection: TextSelection(baseOffset: match.start, extentOffset: match.end),
    ));
  }

  // ---------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final match = search.currentMatch;
    final span = renderer.renderSpan(
      document,
      style: style,
      composingRange: withComposing ? value.composing : null,
      matchHighlightRange: match != null ? TextRange(start: match.start, end: match.end) : null,
    );
    assert(() {
      final renderedLength = span.toPlainText().length;
      if (renderedLength != document.text.length) {
        throw FlutterError(
          'TextSpanRenderer produced a span of $renderedLength characters '
              'but the document text is ${document.text.length} characters. '
              'RenderEditable maps every tap, drag, and selection-handle '
              'position against whatever buildTextSpan returns — a length '
              'mismatch here is exactly the kind of bug that makes selection '
              'and the caret behave incorrectly without any other visible '
              'symptom. Check AttributeStore spans for offsets outside the '
              'current text length.',
        );
      }
      return true;
    }());
    return span;
  }
}