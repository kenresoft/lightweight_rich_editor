import 'package:flutter/material.dart';

import '../clipboard/clipboard_manager.dart';
import '../clipboard/in_memory_rich_clipboard_delegate.dart';
import '../clipboard/rich_clipboard_delegate.dart';
import '../commands/command_dispatcher.dart';
import '../commands/replace_range_command.dart';
import '../commands/set_header_level_command.dart';
import '../core/editing_engine.dart';
import '../core/editor_document.dart';
import '../core/editor_selection.dart';
import '../core/transaction_manager.dart';
import '../export/html_exporter.dart';
import '../export/markdown_exporter.dart';
import '../history/history_manager.dart';
import '../import/html_importer.dart';
import '../import/markdown_importer.dart';
import '../metrics/editor_metrics.dart';
import '../models/attribute_type.dart';
import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';
import '../models/text_attribute.dart';
import '../rendering/render_theme.dart';
import '../rendering/text_span_renderer.dart';
import '../search/search_index.dart';
import '../utils/clamp_int.dart';
import '../utils/link_launcher.dart';
import '../utils/list_prefix.dart';
import '../utils/text_diff.dart';
import '../utils/url_detector.dart';

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
/// 4. Detecting a just-completed URL token at a typing boundary
///    (space/newline/tab) and autolinking it via the same
///    [CommandDispatcher.setLink] path the manual link dialog uses
///    (see [_maybeAutolink]).
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

  /// Whether the host supplied its own `onTapLink` to this constructor,
  /// as opposed to relying on the default ([launchLinkUrl]). Read by
  /// `RichTextEditor` to decide whether it's safe to layer its own
  /// tap-confirmation UI on top of `renderer.onTapLink` — see
  /// `RichTextEditor.confirmBeforeOpeningLinks`. A host that already
  /// asked for custom tap behavior (e.g. routing taps to an in-app
  /// webview) is left completely alone rather than having that
  /// silently wrapped in a confirmation dialog it didn't ask for.
  final bool hasCustomTapHandler;

  /// A visual-only selection range to be rendered even when the editor
  /// loses focus (e.g. while a formatting popup is open).
  TextRange? _selectionHighlight;
  TextRange? get selectionHighlight => _selectionHighlight;

  void setSelectionHighlight(TextRange? range) {
    if (_selectionHighlight == range) return;
    _selectionHighlight = range;
    notifyListeners();
  }

  RichEditorController({
    String text = '',
    List<TextAttribute> initialAttributes = const [],
    FocusNode? focusNode,
    RichTextRenderTheme theme = RichTextRenderTheme.standard,
    Duration typingTimeout = const Duration(milliseconds: 800),
    int maxHistoryLength = 500,
    RichClipboardDelegate? richClipboardDelegate,
    void Function(String url)? onTapLink,
    bool interactiveLinks = false,
  }) : document = EditorDocument.fromText(text, initialAttributes),
       // Defaults to the standard external-browser launcher
       // (`launchLinkUrl`) when the host doesn't supply its own
       // `onTapLink` — so both manually-created and autolinked links
       // are tappable out of the box. Hosts that want different
       // behavior still override it via the constructor param exactly
       // as before; see `hasCustomTapHandler`.
       renderer = TextSpanRenderer(
         theme: theme,
         onTapLink: onTapLink ?? launchLinkUrl,
         interactiveLinks: interactiveLinks,
       ),
       hasCustomTapHandler = onTapLink != null,
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
    clipboard = ClipboardManager(
      document: document,
      commands: commands,
      delegate: richClipboardDelegate ?? InMemoryRichClipboardDelegate.shared,
    );
    metrics = EditorMetrics(document: document, history: history);
    search = SearchIndex(document: document, commands: commands);
    this.focusNode.addListener(_handleFocusChange);
    // Tapping a checkbox glyph toggles that specific paragraph, not
    // whatever the current selection happens to be — same reasoning as
    // routing a link tap through `onTapLink` rather than a selection-based
    // action.
    renderer.onToggleCheckbox = (paragraphStart) {
      _syncSelection(
        commands.toggleTaskItem(EditorSelection.collapsed(paragraphStart)),
      );
    };
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

  /// Forces the editor's underlying platform text-input connection to
  /// re-attach after some *other* interactive widget the host placed
  /// near the editor (a custom app-bar button, a floating action button,
  /// anything outside this library's own [FormatToolbar]) has just been
  /// tapped.
  ///
  /// On Flutter web specifically, tapping practically any interactive
  /// widget elsewhere on the page blurs the editor's hidden text-input
  /// element at the browser level — [focusNode] still reports itself as
  /// focused (Flutter's own bookkeeping is fine), but the OS/browser
  /// text-input connection has been torn down, so the very next
  /// keystroke typed is silently dropped until the user clicks back into
  /// the text. `FormatToolbar`'s own buttons already call this
  /// internally after every action, which is why typing right after
  /// clicking Bold "just works" — a host's *own* UI (a dark-mode toggle
  /// in an app bar is a real example that hits exactly this) doesn't get
  /// that for free, since it isn't part of this library's toolbar. Call
  /// this right after any such interaction your app performs, and the
  /// same fix applies.
  ///
  /// Deliberately a synchronous `unfocus()` immediately followed by
  /// `requestFocus()` — a bare `requestFocus()` alone is a no-op when
  /// Flutter already considers the node focused, and it never re-attaches
  /// the connection; deferring the `requestFocus()` to the next frame
  /// (an earlier approach) works too but paints a visible one-frame
  /// "unfocused" flicker (cursor/selection handles disappearing and
  /// reappearing) that calling both synchronously avoids entirely, since
  /// Flutter's frame pipeline coalesces the two into a single rebuild —
  /// see `FormatToolbar`'s internal `_reclaimEditorFocus` for the full
  /// reasoning and how this was verified live.
  void reclaimFocus() {
    focusNode.unfocus();
    focusNode.requestFocus();
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
  ///
  /// A diff whose entire inserted text is a bare `'\n'` — a live Enter
  /// keypress, indistinguishable at this layer from any other single-
  /// character insertion — is routed through
  /// [EditingEngine.enterKeyEdit] first, so typing Enter inside a
  /// literal list line (`'- '`, `'3. '`, ...) continues or exits the
  /// list as plain text. This is the actual typing path a live
  /// `TextField` takes; [CommandDispatcher.insertText] has the same
  /// hook for programmatic/toolbar-driven insertion, but that method is
  /// never called for ordinary keystrokes — they come through here.
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

    // Flutter's own `newValue.selection` is a guess based on what *it*
    // thinks was inserted — always correct for the ordinary path below,
    // where the document ends up with exactly `diff.insertedText`. The
    // smart-Enter path can insert a longer (or shorter) string than the
    // bare '\n' Flutter guessed for, so that guess is stale the moment
    // it's taken; this computes the real post-edit caret instead of
    // trusting it.
    var resultSelection = newValue.selection;
    var resultComposing = newValue.composing;
    var ranAutolink = false;

    // Defensive safety net, not a substitute for fixing bugs at the
    // source: if anything in this block throws — a real one already
    // did once (an EditingEngine helper returned an immutable list a
    // caller then tried to mutate) — the failure mode is severe enough
    // to guard against explicitly. The exception aborts this method
    // partway through, after Flutter's own EditableText has already
    // applied the keystroke to its internal state but before
    // `document.text`/`super.value` are updated to match. Every
    // subsequent keystroke's diff is then computed against a stale
    // `oldText` that no longer matches what's actually on screen —
    // one crash corrupts the rest of the session, not just the one
    // keystroke. On catch: force the field back to exactly what
    // `document` (left unmodified, since nothing committed) already
    // says, discarding this one keystroke rather than leaving
    // Flutter's state and the engine's state permanently desynced —
    // then rethrow, so the error still surfaces for debugging instead
    // of silently swallowing a real bug.
    try {
      if (!diff.isNoOp) {
        if (diff.insertedText == '\n') {
          // relativeAttributes, not attributesForInsertion: see
          // EditingEngine.enterKeyEditWithRenumber's doc comment — this
          // edit can reconstruct pre-existing text (a mid-line split's
          // tail, renumbered subsequent items), which needs to keep its
          // own original formatting rather than having sticky attributes
          // smeared across the whole combined replacement. Sticky
          // attributes are still applied, just only to the genuinely new
          // marker portion — enterKeyEditWithRenumber folds that into the
          // relativeAttributes it returns, given the current sticky state
          // as a parameter.
          final edit = engine.enterKeyEditWithRenumber(
            EditorSelection(baseOffset: diff.start, extentOffset: diff.end),
            Map.of(engine.stickyAttributes),
          );
          history.execute(
            ReplaceRangeCommand(
              start: edit.start,
              end: edit.end,
              text: edit.text,
              relativeAttributes: edit.relativeAttributes,
            ),
          );
          resultSelection = TextSelection.collapsed(
            offset: edit.start + edit.cursorOffsetFromStart,
          );
          resultComposing = TextRange.empty;
          // Not autolinking here: the exit-list variant deletes the
          // prefix, which shifts everything `_maybeAutolink` assumes
          // about `diff`'s positions still lining up with the document.
          // Narrow trade-off — no autolink on the exact keystroke where
          // Enter also exits a list — over reusing position math that no
          // longer holds.
        } else if (diff.insertedText.isEmpty && diff.end - diff.start == 1) {
          // A single-character deletion — live backspace. Routed through
          // the same consolidated EditingEngine.deleteBackwardEdit the
          // programmatic CommandDispatcher.deleteBackward path uses, so
          // live typing gets smart list-marker removal and numbered-list
          // renumbering too, not just the raw one-character diff. Called
          // with the caret at diff.end (where it was *before* backspacing,
          // matching deleteBackwardEdit's own "collapsed selection at the
          // pre-deletion caret" contract) — document.paragraphs/text still
          // reflect the pre-deletion state here, since nothing has been
          // dispatched yet. relativeAttributes, not attributesForInsertion
          // — same reasoning as the Enter branch above: the renumbering
          // case reconstructs existing paragraphs' text and must keep
          // their own attributes, never sticky ones (there's no "new"
          // portion here the way Enter's marker is, so no sticky
          // application at all makes sense for this specific edit).
          final edit = engine.deleteBackwardEdit(
            EditorSelection.collapsed(diff.end),
          );
          if (edit != null) {
            history.execute(
              ReplaceRangeCommand(
                start: edit.start,
                end: edit.end,
                text: edit.text,
                relativeAttributes: edit.relativeAttributes,
              ),
            );
            resultSelection = TextSelection.collapsed(
              offset: edit.start + edit.cursorOffsetFromStart,
            );
            resultComposing = TextRange.empty;
          } else {
            // Shouldn't happen — diff implies something was deletable —
            // but fall back to the raw diff defensively rather than
            // silently dropping the edit.
            history.execute(
              ReplaceRangeCommand(
                start: diff.start,
                end: diff.end,
                text: diff.insertedText,
                attributesForInsertion: Map.of(engine.stickyAttributes),
              ),
            );
          }
          // Backspace never autolinks — _maybeAutolink no-ops on empty
          // insertedText anyway, but ranAutolink stays false for clarity
          // of intent, not just because the guard happens to catch it.
        } else {
          // Markdown-style header shortcut: a bare '#'/'##'/... at the
          // very start of an otherwise-empty paragraph, followed by the
          // space the user just typed. Checked before the generic
          // handling below, not folded into it — a match consumes the
          // space entirely (never inserted) rather than treating this as
          // ordinary text entry.
          final autoHeaderLevel =
              diff.insertedText == ' ' && diff.start == diff.end
              ? engine.autoFormatHeaderLevel(diff.start)
              : null;

          if (autoHeaderLevel != null) {
            final paragraphStart = document.paragraphs
                .paragraphAt(diff.start)!
                .start;
            // Two separate undo steps, deliberately — same "one keystroke,
            // two commits" trade-off already used below for
            // repairListNumbering's follow-up: stripping the literal
            // '#'/'##' is a text edit, setting headerLevel is metadata: two
            // different kinds of change, restored independently on undo.
            history.execute(
              ReplaceRangeCommand(
                start: paragraphStart,
                end: diff.start,
                text: '',
              ),
            );
            history.execute(
              SetHeaderLevelCommand(
                EditorSelection.collapsed(paragraphStart),
                autoHeaderLevel,
              ),
            );
            resultSelection = TextSelection.collapsed(offset: paragraphStart);
            resultComposing = TextRange.empty;
            // Not autolinking here: there's no text left after becoming a
            // heading for _maybeAutolink to look at.
          } else {
            // A bulk insert (see _maybeAutolink's doc comment: never a
            // live keystroke, always an already-finished chunk) gets its
            // autolinks computed *before* dispatch and folded into this
            // same `ReplaceRangeCommand` as `relativeAttributes`, rather
            // than inserted first and linked after the fact via a
            // separate `commands.setLink` call per URL. A real, reported
            // bug: doing it after the fact put each autolinked URL on
            // the undo stack as its own step, so undoing a single paste
            // took N+1 presses — one per link, plus one for the text —
            // unwinding the links one at a time before ever touching the
            // pasted text itself, instead of the whole paste
            // disappearing on the first undo like every other editor.
            // Single-character live typing (the only other caller of
            // `ranAutolink`) is unaffected — it still goes through
            // `_maybeAutolink`'s separate-command path below exactly as
            // before, since that one *keystroke* being its own undo step
            // (distinct from the autolink it triggers) is a deliberate,
            // pre-existing design choice, not part of this bug.
            final urls = diff.insertedText.length > 1
                ? detectAllUrls(diff.insertedText)
                : const <DetectedUrl>[];

            if (urls.isEmpty) {
              history.execute(
                ReplaceRangeCommand(
                  start: diff.start,
                  end: diff.end,
                  text: diff.insertedText,
                  attributesForInsertion: Map.of(engine.stickyAttributes),
                ),
              );
              ranAutolink = diff.insertedText.length == 1;
            } else {
              final sticky = engine.stickyAttributes;
              final relativeAttributes = <TextAttribute>[
                for (final entry in sticky.entries)
                  if (entry.key != AttributeType.link)
                    TextAttribute(
                      start: 0,
                      end: diff.insertedText.length,
                      type: entry.key,
                      value: entry.value,
                    ),
                for (final u in urls)
                  TextAttribute(start: u.start, end: u.end, type: AttributeType.link, value: u.href),
              ];
              history.execute(
                ReplaceRangeCommand(
                  start: diff.start,
                  end: diff.end,
                  text: diff.insertedText,
                  relativeAttributes: relativeAttributes,
                ),
              );
              ranAutolink = false;
            }

            // Same "range edit can orphan a numbered run" concern as
            // CommandDispatcher.deleteSelection — this branch is what
            // actually runs when a real device backspaces over a
            // multi-paragraph selection (or types over one), not the
            // programmatic path, so it needs the same follow-up check.
            // Two separate undo steps when a repair is needed, same
            // reasoning as CommandDispatcher.deleteSelection's doc comment.
            // Not relying on history.execute's return value here — every
            // other call site in this file discards it too, and computing
            // the post-edit position directly from diff (start + however
            // much was inserted) is exactly where the merge boundary
            // landed regardless.
            final repairEdit = engine.repairListNumbering(
              EditorSelection.collapsed(diff.start + diff.insertedText.length),
            );
            if (repairEdit != null) {
              history.execute(
                ReplaceRangeCommand(
                  start: repairEdit.start,
                  end: repairEdit.end,
                  text: repairEdit.text,
                  relativeAttributes: repairEdit.relativeAttributes,
                ),
              );
            }
          }
        }
      }
    } catch (_) {
      super.value = TextEditingValue(
        text: document.text,
        selection: TextSelection.collapsed(
          offset: clampInt(newValue.selection.start, 0, document.length),
        ),
      );
      rethrow;
    }

    // Trust the TextField/IME's own reported selection for where the
    // caret actually lands — autocorrect and IME composition can put it
    // somewhere `diff` alone wouldn't predict. Only valid on the
    // ordinary path above, where `resultSelection`/`resultComposing`
    // still equal Flutter's own values; the smart-Enter path already
    // overrode both for the reason noted there.
    super.value = TextEditingValue(
      text: document.text,
      selection: resultSelection,
      composing: resultComposing,
    );

    if (ranAutolink) {
      _maybeAutolink(diff);
    }
  }

  /// After a single-character live keystroke, checks whether it just
  /// completed an autolink boundary (space/newline/tab) and, if the
  /// token immediately before that boundary is a confidently URL-shaped
  /// token, applies the link attribute over it via
  /// [CommandDispatcher.setLink] — the exact same path the manual link
  /// dialog uses, so an autolinked URL is its own undo step and is
  /// editable/removable exactly like a manually-inserted link.
  ///
  /// Only ever called for a genuine one-character diff — every other
  /// caller of `ranAutolink` is a *bulk* insert (never a live keystroke;
  /// always an already-finished chunk arriving as one atomic unit — a
  /// real device's own keyboard pasting directly via its clipboard
  /// suggestion, autocomplete, voice input), which computes and applies
  /// its own autolinks *before* dispatch instead, baked into the very
  /// same `ReplaceRangeCommand` as `relativeAttributes` — see the `set
  /// value` override's general-insert branch. That split exists because
  /// this method's contract — undo the *character* and the *link* it
  /// triggered as two separate steps — is a deliberate, pre-existing
  /// design choice for live typing, but is exactly the bug a bulk paste
  /// hit: doing it after the fact, one `setLink` call per URL, put every
  /// autolinked URL from a single paste on the undo stack as its own
  /// step, so undoing the paste took N+1 presses instead of one.
  ///
  /// Only ever inspects the single token immediately before the
  /// boundary that was just typed — never the whole document — which is
  /// what keeps this from firing while a URL is still being typed: a
  /// boundary char has to have actually just been inserted for
  /// `diff.insertedText` to end with one, and no URL contains a
  /// space/newline/tab.
  ///
  /// Deliberately runs *after* `super.value = ...` in `set value` rather
  /// than before. By the time `commands.setLink` fires
  /// `transactions.notify()` -> `_handleCommit` -> `_applyValue`,
  /// `this.selection` already equals the correct, final, IME-reported
  /// selection — so `_handleCommit`'s clamp-and-reapply computes a
  /// genuine no-op `TextEditingValue`, and `_applyValue` takes the
  /// documented "notify anyway" path for pure-formatting changes,
  /// instead of momentarily computing a stale, pre-edit-selection
  /// guess and then immediately overwriting it.
  void _maybeAutolink(TextDiff diff) {
    if (diff.insertedText.isEmpty) return;
    final lastChar = diff.insertedText[diff.insertedText.length - 1];
    if (!isAutolinkBoundary(lastChar)) return;

    final boundaryIndex = diff.start + diff.insertedText.length - 1;
    final detected = detectUrlBeforeBoundary(document.text, boundaryIndex);
    if (detected == null) return;

    final existing = document.attributeStore.findIntersecting(
      detected.start,
      detected.end,
      type: AttributeType.link,
    );
    if (existing.isNotEmpty) {
      final link = existing.first;
      if (link.start == detected.start &&
          link.end == detected.end &&
          link.value == detected.href) {
        return;
      }
    }

    commands.setLink(
      EditorSelection(baseOffset: detected.start, extentOffset: detected.end),
      detected.href,
    );

    // Defensive: make sure the next keystroke starts a fresh
    // typing/coalescing session rather than risking a merge with
    // whatever's now on top of the undo stack.
    history.breakCoalescing();
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
    _applyValue(
      value.copyWith(
        text: newText,
        selection: clamped,
        composing: newText == value.text ? value.composing : TextRange.empty,
      ),
    );
  }

  void _syncSelection(EditorSelection result) {
    _applyValue(
      value.copyWith(
        text: document.text,
        selection: _toTextSelection(result),
        composing: TextRange.empty,
      ),
    );
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
    if (_selectionHighlight != null && _selectionHighlight!.isValid) {
      return EditorSelection(
        baseOffset: _selectionHighlight!.start,
        extentOffset: _selectionHighlight!.end,
      );
    }
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

  void insertText(String text) =>
      _syncSelection(commands.insertText(_currentSelection, text));

  void deleteBackward() =>
      _syncSelection(commands.deleteBackward(_currentSelection));

  void deleteForward() =>
      _syncSelection(commands.deleteForward(_currentSelection));

  /// Deletes the current selection outright. No-op if the selection is
  /// collapsed. Prefer this over `deleteBackward()` at call sites (like
  /// cut) that mean "delete what's selected" — `deleteBackward` happens
  /// to fall back to the same behavior for a non-collapsed selection,
  /// but that's an implementation detail, not something a call site
  /// should rely on to read clearly.
  void deleteSelection() =>
      _syncSelection(commands.deleteSelection(_currentSelection));

  /// Pastes `text` as plain content at the current selection — the
  /// programmatic equivalent of typing it in.
  ///
  /// Any bare URL inside `text` is autolinked immediately, the same as
  /// [paste] (the system-clipboard path, via `ClipboardManager`) already
  /// does — a real, reported bug: only `ClipboardManager.paste()` ran
  /// autolink detection, so any paste path that doesn't go through the
  /// OS clipboard (drag-and-drop, a share-sheet handoff, a host's own
  /// "insert this text" action) left a pasted URL sitting there unlinked
  /// until the user happened to type a boundary character (space,
  /// newline, tab — never actually "Enter" specifically, despite how
  /// that's sometimes described) right after it.
  ///
  /// `text` is normalized to '\n' line endings before anything else runs
  /// — a host calling this with clipboard- or drag-and-drop-sourced text
  /// (its own doc comment above already names both as expected callers)
  /// may well be handing over '\r\n', same as `ClipboardManager.paste`'s
  /// own text can be; see that method's doc comment for the full
  /// explanation of why an un-normalized '\r' silently breaks autolink
  /// detection for every URL on the affected line, not just malformats
  /// the text itself.
  void pasteText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final urls = detectAllUrls(normalized);
    if (urls.isEmpty) {
      _repairAndSync(commands.paste(_currentSelection, normalized));
      return;
    }

    // The non-URL portion of `text` still inherits whatever sticky
    // formatting (bold, an active color, ...) ordinary typing would —
    // this method is meant to behave like typing `text` in one go, not
    // like a rich external paste bringing its own formatting (that's
    // [pasteRichText]/[pasteHtml]/[pasteMarkdown]'s job).
    // AttributeType.link is deliberately excluded from that inherited
    // set: a stale sticky link value (see EditingEngine.applyAttribute's
    // doc comment on why that no longer persists past a range apply,
    // but collapsed-caret sticky link state is still legitimate) must
    // never compete with the URLs actually detected in `text` below.
    final sticky = engine.stickyAttributes;
    final relativeAttributes = <TextAttribute>[
      for (final entry in sticky.entries)
        if (entry.key != AttributeType.link)
          TextAttribute(start: 0, end: normalized.length, type: entry.key, value: entry.value),
      for (final u in urls)
        TextAttribute(start: u.start, end: u.end, type: AttributeType.link, value: u.href),
    ];
    _repairAndSync(commands.pasteRich(_currentSelection, normalized, relativeAttributes));
  }

  void pasteRichText(String text, List<TextAttribute> relativeAttributes) =>
      _repairAndSync(
        commands.pasteRich(_currentSelection, text, relativeAttributes),
      );

  /// Parses `markdown` (a deliberately scoped subset — see
  /// [MarkdownImporter]) and pastes the result at the current selection.
  void pasteMarkdown(String markdown) {
    final parsed = const MarkdownImporter().parse(markdown);
    _repairAndSync(
      commands.pasteRich(_currentSelection, parsed.text, parsed.attributes),
    );
  }

  /// Parses `html` (see [HtmlImporter] for what's recognized) and pastes
  /// the result at the current selection.
  ///
  /// This library doesn't source `html` for you — Flutter's built-in
  /// `Clipboard` API doesn't reliably expose HTML content across
  /// platforms without a plugin (e.g. `super_clipboard`). Call this once
  /// your app has obtained an HTML string some other way (a clipboard
  /// plugin, a platform channel, drag-and-drop, a web `paste` event).
  void pasteHtml(String html) {
    final parsed = const HtmlImporter().parse(html);
    _repairAndSync(
      commands.pasteRich(_currentSelection, parsed.text, parsed.attributes),
    );
  }

  /// Copies the current selection to the system clipboard (and to
  /// [clipboard]'s delegate, if one is set, preserving formatting). See
  /// [ClipboardManager.copy].
  Future<void> copy() => clipboard.copy(_currentSelection);

  /// Copies then deletes the current selection. See [ClipboardManager.cut].
  Future<void> cut() async =>
      _syncSelection(await clipboard.cut(_currentSelection));

  /// Pastes at the current selection — rich content if [clipboard] has a
  /// matching delegate entry, otherwise plain text from the system
  /// clipboard. See [ClipboardManager.paste].
  Future<void> paste() async {
    final result = await clipboard.paste(_currentSelection);
    if (result != null) _repairAndSync(result);
  }

  /// Syncs selection, then checks whether the paragraph the paste/import
  /// landed in (or the one right after it) is part of a numbered run
  /// whose markers are no longer sequential, and repairs it if so — see
  /// `EditingEngine.repairListNumbering`'s doc comment. This is the
  /// "Paste and Import" half of that method's intended use; the other
  /// half (range deletions orphaning a run) is handled directly in
  /// `CommandDispatcher.deleteSelection` and this class's `set value`.
  ///
  /// External content is the case this matters most for: pasted or
  /// imported text can arrive with numbering that was never generated
  /// by this editor's own toggle/renumber logic at all (a list typed in
  /// some other app, an inconsistently-numbered HTML/Markdown source),
  /// so there's no guarantee it was ever sequential to begin with —
  /// unlike this editor's own edits, which stay self-consistent by
  /// construction.
  void _repairAndSync(EditorSelection resultSelection) {
    _syncSelection(resultSelection);
    final edit = engine.repairListNumbering(resultSelection);
    if (edit == null) return;
    _syncSelection(
      commands.pasteRich(
        EditorSelection(baseOffset: edit.start, extentOffset: edit.end),
        edit.text,
        edit.relativeAttributes,
      ),
    );
  }

  void toggleBold() => commands.toggleBold(_currentSelection);

  /// Exports the current document as an HTML string.
  ///
  /// Uses [EditorDocument.exportAttributes] rather than
  /// [EditorDocument.attributes] directly — header formatting is read
  /// from `document.paragraphs` now (Phase 3 of the block-architecture
  /// migration), and `exportAttributes` is what synthesizes that back
  /// into the flat span list `HtmlExporter` itself is unchanged and
  /// still expects.
  String toHtml() =>
      const HtmlExporter().export(document.text, document.exportAttributes());

  /// Exports the current document as a Markdown string. See [toHtml]'s
  /// doc comment — same reasoning applies here.
  String toMarkdown() => const MarkdownExporter().export(
    document.text,
    document.exportAttributes(),
  );
  void toggleItalic() => commands.toggleItalic(_currentSelection);
  void toggleUnderline() => commands.toggleUnderline(_currentSelection);
  void toggleStrikethrough() => commands.toggleStrikethrough(_currentSelection);
  void toggleHighlight() => commands.toggleHighlight(_currentSelection);
  void toggleCode() => commands.toggleCode(_currentSelection);

  void toggleBulletList() =>
      _syncSelection(commands.toggleBulletList(_currentSelection));
  void toggleNumberedList() =>
      _syncSelection(commands.toggleNumberedList(_currentSelection));
  void indentList() => _syncSelection(commands.indentList(_currentSelection));
  void outdentList() => _syncSelection(commands.outdentList(_currentSelection));

  /// Whether the paragraph containing the current selection starts with
  /// a literal prefix of `type` — drives the list toolbar buttons'
  /// active state. Purely derived from text (`listPrefixLength`/
  /// `listTypeOfPrefix`), same as rendering and `enterKeyEdit` — no
  /// stored list state to read.
  bool isListActive(ParagraphListType type) {
    final sel = _currentSelection;
    final record = document.paragraphs.paragraphAt(sel.start);
    if (record == null) return false;
    final prefixLen = listPrefixLength(document.text, record.start);
    if (prefixLen == 0) return false;
    return listTypeOfPrefix(
          document.text.substring(record.start, record.start + prefixLen),
        ) ==
        type;
  }

  void toggleTaskItem() =>
      _syncSelection(commands.toggleTaskItem(_currentSelection));

  /// Whether the paragraph containing the current selection is a
  /// task-list item, and if so, whether it's checked — `null` if it
  /// isn't a checklist item at all. Purely derived from text
  /// ([checkboxStateOfPrefix]), same as [isListActive] — no stored
  /// checked state to read. Drives the checklist toolbar button/toggle's
  /// display state.
  bool? isTaskChecked() {
    final sel = _currentSelection;
    final record = document.paragraphs.paragraphAt(sel.start);
    if (record == null) return null;
    final prefixLen = listPrefixLength(document.text, record.start);
    if (prefixLen == 0) return null;
    return checkboxStateOfPrefix(
      document.text.substring(record.start, record.start + prefixLen),
    );
  }

  void setColor(int? argb) => commands.setColor(_currentSelection, argb);
  void setSize(num? size) => commands.setSize(_currentSelection, size);

  void increaseFontSize() {
    final current =
        activeAttributeValue(AttributeType.size) as num? ??
        renderer.theme.baseFontSize;
    setSize((current.toDouble() + 2.0).clamp(8.0, 72.0));
  }

  void decreaseFontSize() {
    final current =
        activeAttributeValue(AttributeType.size) as num? ??
        renderer.theme.baseFontSize;
    setSize((current.toDouble() - 2.0).clamp(8.0, 72.0));
  }

  void setLink(String? url) => commands.setLink(_currentSelection, url);
  void setHeader(String? level) => commands.setHeader(_currentSelection, level);
  void setAlignment(ParagraphAlignment? alignment) =>
      commands.setAlignment(_currentSelection, alignment);
  void setTextDirection(ParagraphTextDirection? textDirection) =>
      commands.setTextDirection(_currentSelection, textDirection);

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
  ///
  /// For [AttributeType.header] this delegates entirely to
  /// [activeAttributeValue] — header no longer lives in
  /// [EditorDocument.attributeStore] at all (see the block-architecture
  /// design notes), so the generic `attributeStore`-based logic below
  /// would silently go stale the moment a heading is set via
  /// `CommandDispatcher.setHeader`.
  bool isAttributeActive(AttributeType type) {
    if (type == AttributeType.header ||
        type == AttributeType.align ||
        type == AttributeType.textDirection) {
      return activeAttributeValue(type) != null;
    }
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
  ///
  /// [AttributeType.header] reads from [EditorDocument.paragraphs]
  /// instead of `attributeStore` — same reasoning as
  /// [isAttributeActive]. "Active" for a multi-paragraph selection
  /// means every paragraph the selection touches agrees on the same
  /// `headerLevel`, mirroring what the old `attributeStore`-based
  /// `coversRange`/`covers` check meant: a value only counts as active
  /// if it uniformly covers the whole selection, not just part of it.
  Object? activeAttributeValue(AttributeType type) {
    if (type == AttributeType.header) {
      final sel = _currentSelection;
      final startRecord = document.paragraphs.paragraphAt(sel.start);
      if (startRecord == null) return null;
      if (sel.isCollapsed) return startRecord.headerLevel;
      final overlapping = document.paragraphs.recordsOverlapping(
        sel.start,
        sel.end,
      );
      if (overlapping.isEmpty) return null;
      final level = overlapping.first.headerLevel;
      final allAgree = overlapping.every((r) => r.headerLevel == level);
      return allAgree ? level : null;
    }
    if (type == AttributeType.align) {
      final sel = _currentSelection;
      final startRecord = document.paragraphs.paragraphAt(sel.start);
      if (startRecord == null) return null;
      if (sel.isCollapsed) return startRecord.alignment;
      final overlapping = document.paragraphs.recordsOverlapping(
        sel.start,
        sel.end,
      );
      if (overlapping.isEmpty) return null;
      final alignment = overlapping.first.alignment;
      final allAgree = overlapping.every((r) => r.alignment == alignment);
      return allAgree ? alignment : null;
    }
    if (type == AttributeType.textDirection) {
      final sel = _currentSelection;
      final startRecord = document.paragraphs.paragraphAt(sel.start);
      if (startRecord == null) return null;
      if (sel.isCollapsed) return startRecord.textDirection;
      final overlapping = document.paragraphs.recordsOverlapping(
        sel.start,
        sel.end,
      );
      if (overlapping.isEmpty) return null;
      final textDirection = overlapping.first.textDirection;
      final allAgree = overlapping.every(
        (r) => r.textDirection == textDirection,
      );
      return allAgree ? textDirection : null;
    }
    final sel = _currentSelection;
    if (sel.isCollapsed) {
      if (engine.stickyAttributes.containsKey(type)) {
        return engine.stickyAttributes[type];
      }
      final at = document.attributeStore.findAt(sel.start, type: type);
      return at.isEmpty ? null : at.first.value;
    }
    final covering = document.attributeStore
        .findIntersecting(sel.start, sel.end, type: type)
        .where((s) => s.covers(sel.start, sel.end));
    return covering.isEmpty ? null : covering.first.value;
  }

  /// The link URL at [offset], or `null` if [offset] isn't inside a
  /// link attribute.
  ///
  /// Checks both `offset` and `offset - 1`. A single tap's resulting
  /// caret offset lands wherever `RenderEditable` rounds to the
  /// nearest character boundary — tapping the *right half* of a
  /// link's very last character is a completely ordinary way to tap
  /// "on" that link, and it produces `offset == link.end`, not
  /// `link.end - 1`. Checking only `offset` would silently miss that
  /// (common) case. The trade-off: a tap intended to place the caret
  /// just *after* a link (to keep typing) at that exact same boundary
  /// offset is indistinguishable from a tap "on" the link's last
  /// character — this is inherently ambiguous from offset alone, the
  /// same ambiguity Google Docs/Notion have at a link's edge. Pairing
  /// this with a confirmation dialog before actually launching (see
  /// `RichTextEditor`) is what makes that ambiguity harmless rather
  /// than something that needs pixel-perfect resolution here.
  String? linkUrlAt(int offset) {
    if (offset < 0) return null;
    final atOffset = document.attributeStore.findAt(
      offset,
      type: AttributeType.link,
    );
    if (atOffset.isNotEmpty) return atOffset.first.value as String?;
    if (offset > 0) {
      final beforeOffset = document.attributeStore.findAt(
        offset - 1,
        type: AttributeType.link,
      );
      if (beforeOffset.isNotEmpty) return beforeOffset.first.value as String?;
    }
    return null;
  }

  /// The logical range of the link at [offset], or `null` if [offset]
  /// isn't inside a link attribute.
  TextRange? linkRangeAt(int offset) {
    if (offset < 0) return null;
    final atOffset = document.attributeStore.findAt(
      offset,
      type: AttributeType.link,
    );
    if (atOffset.isNotEmpty) {
      return TextRange(start: atOffset.first.start, end: atOffset.first.end);
    }
    if (offset > 0) {
      final beforeOffset = document.attributeStore.findAt(
        offset - 1,
        type: AttributeType.link,
      );
      if (beforeOffset.isNotEmpty) {
        return TextRange(
          start: beforeOffset.first.start,
          end: beforeOffset.first.end,
        );
      }
    }
    return null;
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
    _applyValue(
      TextEditingValue(
        text: document.text,
        selection: const TextSelection.collapsed(offset: 0),
      ),
    );
  }

  Map<String, dynamic> toJson() => document.toJson();

  // ---------------------------------------------------------------------
  // Find & replace
  // ---------------------------------------------------------------------

  /// Runs a new search and, if there's a match, selects it in the
  /// editor. See [SearchIndex.search].
  void find(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
  }) {
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
    _applyValue(
      value.copyWith(
        selection: TextSelection(
          baseOffset: match.start,
          extentOffset: match.end,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------

  // Converted from `search.matches` (a `List<SearchMatch>`, Flutter-free
  // by design — see `SearchIndex`'s own doc comment) to the `TextRange`s
  // `TextSpanRenderer.renderSpan` actually wants. Memoized by reference
  // to the *source* list rather than recomputed every `buildTextSpan`
  // call: `SearchIndex.matches` already returns a stable reference that
  // only changes when the match set itself does, and `renderSpan`'s own
  // cache compares `allMatchesRanges` by `identical()` — recomputing a
  // fresh list here on every call (even with identical matches) would
  // silently defeat that cache on every keystroke while a search is
  // active.
  List<SearchMatch>? _allMatchesRangesSource;
  List<TextRange>? _allMatchesRanges;

  List<TextRange>? get _currentAllMatchesRanges {
    final source = search.matches;
    if (source.isEmpty) return null;
    if (!identical(_allMatchesRangesSource, source)) {
      _allMatchesRangesSource = source;
      _allMatchesRanges = source
          .map((m) => TextRange(start: m.start, end: m.end))
          .toList(growable: false);
    }
    return _allMatchesRanges;
  }

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
      matchHighlightRange: match != null
          ? TextRange(start: match.start, end: match.end)
          : null,
      selectionHighlightRange: _selectionHighlight,
      allMatchesRanges: _currentAllMatchesRanges,
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
