import 'package:flutter/material.dart';

import '../clipboard/clipboard_manager.dart';
import '../clipboard/in_memory_rich_clipboard_delegate.dart';
import '../clipboard/native/rich_clipboard_platform.dart';
import '../clipboard/rich_clipboard_delegate.dart';
import '../commands/command_dispatcher.dart';
import '../commands/composite_command.dart';
import '../commands/editor_command.dart';
import '../commands/renumber_lists_command.dart';
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
import '../rendering/ruled_row_metrics.dart';
import '../rendering/text_span_renderer.dart';
import '../search/search_index.dart';
import '../utils/clamp_int.dart';
import '../models/code_block.dart';
import '../models/image_block.dart';
import '../images/rich_image_cache.dart';
import '../images/rich_image_store.dart';
import 'image_actions.dart';
import '../utils/link_launcher.dart';
import '../utils/list_prefix.dart';
import '../utils/text_diff.dart';
import '../utils/url_detector.dart';

/// The public API of the editor: a [TextEditingController] that
/// coordinates [EditorDocument], [EditingEngine], [HistoryManager]/
/// [CommandDispatcher], [TextSpanRenderer], and [ClipboardManager].
///
/// Deliberately thin — editing logic, span math, undo grouping, style
/// resolution, and clipboard handling all live in the component built
/// for it. This class owns only what makes sense at the `TextField`
/// boundary: diffing `TextField`'s before/after text into
/// [ReplaceRangeCommand]s, converting between Flutter's [TextSelection]
/// and the engine's [EditorSelection], keeping [TextEditingController.value]
/// in sync via [_handleCommit], and autolinking a just-completed URL
/// token at a typing boundary (see [_maybeAutolink]).
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

  /// A listenable that only triggers when the document's text or
  /// formatting has changed, ignoring pure selection/caret movements.
  /// Useful for expensive re-layouts (like ruled lines) that don't
  /// depend on selection.
  late final ChangeNotifier documentMutationNotifier;

  RichImageStore? _imageStore;

  /// Where this document's pictures are kept. Set before the editor is shown to
  /// enable pasting and drawing images; `null` (the default) means the editor
  /// has no image support and ignores image clipboard content.
  RichImageStore? get imageStore => _imageStore;
  set imageStore(RichImageStore? store) {
    if (identical(store, _imageStore)) return;
    imageCache?.dispose();
    _imageStore = store;
    imageCache = store == null ? null : RichImageCache(store);
    clipboard.acceptImages = store != null;
    notifyListeners();
  }

  /// Told when the pictures of a paste or import have all been dealt with (so the host
  /// can say how many could not be had, or that the page had more than the limit).
  void Function(ImageImportReport report)? onImagesImported;

  /// The most pictures one paste or import brings in (at most [maxImportedImages]); a
  /// host can lower it, for example for a free tier.
  int get importedImageLimit => clipboard.importedImageLimit;
  set importedImageLimit(int value) => clipboard.importedImageLimit = value.clamp(0, maxImportedImages);

  /// The most picture data one paste brings in (see [maxImportedImageBytes]).
  int importedImageByteBudget = maxImportedImageBytes;

  /// Whether [dispose] has run (asynchronous work finishing later must not touch
  /// a disposed controller).
  bool disposed = false;

  /// Decoded pictures for the paper layer (bounded; see [RichImageCache]).
  RichImageCache? imageCache;

  /// Whether the host supplied its own `onTapLink` to this constructor,
  /// as opposed to relying on the default ([launchLinkUrl]). Read by
  /// `RichTextEditor` to decide whether it's safe to layer its own
  /// tap-confirmation UI on top of `renderer.onTapLink`.
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
       // Defaults to the standard external-browser launcher when the
       // host doesn't supply its own onTapLink; see hasCustomTapHandler.
       renderer = TextSpanRenderer(
         theme: theme,
         onTapLink: onTapLink ?? launchLinkUrl,
         interactiveLinks: interactiveLinks,
       ),
       hasCustomTapHandler = onTapLink != null,
       focusNode = focusNode ?? FocusNode(),
       _ownsFocusNode = focusNode == null,
       super(text: text) {
    documentMutationNotifier = ChangeNotifier();
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
    // whatever the current selection happens to be.
    renderer.onToggleCheckbox = (paragraphStart) {
      _syncSelection(
        commands.toggleTaskItem(EditorSelection.collapsed(paragraphStart)),
      );
    };
  }

  void _handleFocusChange() {
    // Reserved for future focus-driven behavior. No-op today.
  }

  @override
  void dispose() {
    disposed = true;
    focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) focusNode.dispose();
    documentMutationNotifier.dispose();
    renderer.dispose();
    imageCache?.dispose();
    super.dispose();
  }

  /// Forces the editor's underlying platform text-input connection to
  /// re-attach after some *other* interactive widget near the editor
  /// (outside this library's own [FormatToolbar]) has just been tapped.
  ///
  /// On Flutter web, tapping another interactive widget elsewhere on the
  /// page blurs the editor's hidden text-input element at the browser
  /// level even though [focusNode] still reports itself as focused, so
  /// the next keystroke is silently dropped until the user clicks back
  /// in. Call this right after any such interaction your app performs.
  ///
  /// Deliberately a synchronous `unfocus()` immediately followed by
  /// `requestFocus()`: a bare `requestFocus()` is a no-op when Flutter
  /// already considers the node focused, and deferring to the next frame
  /// paints a visible unfocused flicker that the synchronous pair avoids.
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
  /// This is the only place raw text-diffing happens: it figures out
  /// *what* changed via [diffText], turns that into one
  /// [ReplaceRangeCommand], and lets [HistoryManager] decide whether it
  /// coalesces with the in-progress typing session. Selection-only
  /// changes skip straight to syncing sticky formatting.
  ///
  /// A diff whose entire inserted text is a bare `'\n'` is routed
  /// through [EditingEngine.enterKeyEdit] first, so typing Enter inside
  /// a literal list line continues or exits the list as plain text.
  @override
  set value(TextEditingValue newValue) {
    final oldText = document.text;
    final newText = newValue.text;

    if (oldText == newText) {
      newValue = newValue.copyWith(selection: _outOfMarker(newValue.selection));
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

    // Image rows are not text: typing, Enter or a delete aimed at one acts on the
    // picture (or moves out of it) instead of writing into its blank rows.
    if (!diff.isNoOp && document.paragraphs.hasAnyImage) {
      final handled = _guardImageEdit(diff);
      if (handled != null) {
        history.breakCoalescing();
        super.value = TextEditingValue(text: document.text, selection: handled);
        return;
      }
    }

    // newValue.selection is Flutter's guess based on a bare '\n'; the
    // smart-Enter path below can insert a longer/shorter string, so this
    // gets overwritten with the real post-edit caret where needed.
    var resultSelection = newValue.selection;
    var resultComposing = newValue.composing;
    var shift = 0; // how far renumbering moved the caret (a "9." that became "10.")
    var ranAutolink = false;
    int? enterBoundary; // Enter pressed right after text: the line it ends may end in an address

    // If anything in this block throws, Flutter's EditableText has
    // already applied the keystroke internally but document/super.value
    // haven't been updated to match, so every later diff would run
    // against a stale oldText. On catch: force the field back to exactly
    // what `document` (left unmodified) already says, then rethrow.
    try {
      if (!diff.isNoOp) {
        // A deletion that stops inside the next line's marker takes the whole marker, so no half of
        // one is left in the text.
        final cutEnd = diff.insertedText.isEmpty ? engine.endOutsideMarker(diff.end) : diff.end;
        final codeExit = diff.insertedText == '\n'
            ? commands.exitCodeBlock(EditorSelection(baseOffset: diff.start, extentOffset: diff.end))
            : null;
        if (codeExit != null) {
          resultSelection = TextSelection.collapsed(offset: codeExit.start);
          resultComposing = TextRange.empty;
        } else if (diff.insertedText == '\n') {
          // relativeAttributes, not attributesForInsertion: this edit may
          // reconstruct pre-existing text that must keep its own
          // formatting rather than having sticky attributes smeared
          // across the whole combined replacement.
          final edit = engine.enterKeyEditWithRenumber(
            EditorSelection(baseOffset: diff.start, extentOffset: diff.end),
            Map.of(engine.stickyAttributes),
          );
          final settled = commands.dispatchRenumbered(
            ReplaceRangeCommand(
              start: edit.start,
              end: edit.end,
              text: edit.text,
              relativeAttributes: edit.relativeAttributes,
              stripAttributes: engine.stickyOff,
            ),
            from: edit.start,
            to: edit.end,
            caret: edit.start + edit.cursorOffsetFromStart,
          );
          resultSelection = TextSelection.collapsed(offset: settled.start);
          resultComposing = TextRange.empty;
          // The exit-list variant deletes the list prefix, shifting positions, so only a plain
          // line break (the new line break sits exactly where Enter was pressed) links the
          // address before it, below, once the value is set.
          if (edit.start == diff.start && diff.start < document.length && document.text[diff.start] == '\n') {
            enterBoundary = diff.start;
          }
        } else if (diff.insertedText.isEmpty && diff.end - diff.start == 1) {
          // Live backspace, routed through the same
          // EditingEngine.deleteBackwardEdit the programmatic
          // CommandDispatcher.deleteBackward path uses, for smart
          // list-marker removal and renumbering. Called with the caret at
          // diff.end (the pre-deletion caret), since nothing has been
          // dispatched yet.
          final edit = engine.deleteBackwardEdit(
            EditorSelection.collapsed(diff.end),
          );
          if (edit != null) {
            final settled = commands.dispatchRenumbered(
              ReplaceRangeCommand(
                start: edit.start,
                end: edit.end,
                text: edit.text,
                relativeAttributes: edit.relativeAttributes,
              ),
              from: edit.start,
              to: edit.end,
              caret: edit.start + edit.cursorOffsetFromStart,
            );
            resultSelection = TextSelection.collapsed(offset: settled.start);
            resultComposing = TextRange.empty;
          } else {
            // Shouldn't happen — diff implies something was deletable —
            // but fall back to the raw diff defensively.
            history.execute(
              ReplaceRangeCommand(
                start: diff.start,
                end: cutEnd,
                text: diff.insertedText,
                attributesForInsertion: Map.of(engine.stickyAttributes),
              ),
            );
          }
        } else {
          // Markdown-style header shortcut: a bare '#'/'##'/... at the
          // start of an otherwise-empty paragraph, followed by the space
          // just typed. A match consumes the space entirely rather than
          // treating this as ordinary text entry.
          final autoHeaderLevel =
              diff.insertedText == ' ' && diff.start == diff.end
              ? engine.autoFormatHeaderLevel(diff.start)
              : null;

          if (autoHeaderLevel != null) {
            final paragraphStart = document.paragraphs
                .paragraphAt(diff.start)!
                .start;
            // Two separate undo steps: stripping the '#'/'##' is a text
            // edit, setting headerLevel is metadata — restored
            // independently on undo.
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
            // Not autolinking here: no text is left after becoming a
            // heading for _maybeAutolink to look at.
          } else {
            // A bulk insert gets its autolinks computed *before* dispatch
            // and folded into this same ReplaceRangeCommand as
            // relativeAttributes, rather than linked after the fact via a
            // separate commands.setLink call per URL — otherwise each
            // autolinked URL becomes its own undo step, so undoing a
            // single paste takes N+1 presses instead of one. Single-
            // character live typing still goes through _maybeAutolink's
            // separate-command path below, unaffected.
            final urls = diff.insertedText.length > 1
                ? detectAllUrls(diff.insertedText)
                : const <DetectedUrl>[];

            if (urls.isEmpty) {
              shift = _executeText(
                ReplaceRangeCommand(
                  start: diff.start,
                  end: cutEnd,
                  text: diff.insertedText,
                  attributesForInsertion: Map.of(engine.stickyAttributes),
                  stripAttributes: engine.stickyOff,
                ),
                diff,
                oldText,
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
              shift = _executeText(
                ReplaceRangeCommand(
                  start: diff.start,
                  end: cutEnd,
                  text: diff.insertedText,
                  relativeAttributes: relativeAttributes,
                  stripAttributes: engine.stickyOff,
                ),
                diff,
                oldText,
              );
              ranAutolink = false;
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

    if (shift != 0) {
      resultSelection = TextSelection(
        baseOffset: resultSelection.baseOffset + shift,
        extentOffset: resultSelection.extentOffset + shift,
      );
    }

    // Trust the TextField/IME's own reported selection where it wasn't
    // overridden above — autocorrect and IME composition can put the
    // caret somewhere `diff` alone wouldn't predict.
    super.value = TextEditingValue(
      text: document.text,
      selection: resultSelection,
      composing: resultComposing,
    );

    if (ranAutolink) {
      _maybeAutolink(diff);
    } else if (enterBoundary != null) {
      _linkAddressBefore(enterBoundary);
    }
  }

  static final RegExp _numberedLine = RegExp(r'^[ \t]*\d{1,9}\. ', multiLine: true);

  /// Runs a typed or pasted text edit. One that spans lines, in or into a list, also renumbers
  /// the lists around it as the same undo step; any other stays a plain command, so typing keeps
  /// grouping into one undo step. Returns how far the caret moved because digits changed length.
  int _executeText(ReplaceRangeCommand command, TextDiff diff, String oldText) {
    final multiLine = diff.insertedText.contains('\n') || oldText.substring(diff.start, diff.end).contains('\n');
    if (!multiLine || !(engine.touchesList(diff.start, diff.end) || _numberedLine.hasMatch(diff.insertedText))) {
      history.execute(command);
      return 0;
    }
    final caret = diff.start + diff.insertedText.length;
    final settled = history.execute(CompositeCommand([command, RenumberListsCommand(around: caret, caret: caret)]));
    return settled.start - caret;
  }

  /// A caret placed in a list item's indentation or marker (a tap at the left edge, Home, an
  /// arrow key) goes to where the item's text starts: typing there would break the marker
  /// (`-x item`, `x- item`). Left from the start of an item's text goes to the end of the line
  /// above instead, so the arrow key is never stuck behind the marker. A selection is left alone.
  TextSelection _outOfMarker(TextSelection sel) {
    if (!sel.isValid || !sel.isCollapsed) return sel;
    final record = document.paragraphs.paragraphAt(sel.baseOffset);
    if (record == null || isCodeBlockLevel(record.headerLevel)) return sel;
    final markerEnd = record.start + listPrefixLength(document.text, record.start);
    if (markerEnd == record.start || sel.baseOffset >= markerEnd) return sel;
    final before = selection;
    final movedLeft = before.isValid && before.isCollapsed && before.baseOffset == markerEnd;
    final target = movedLeft && record.start > 0 ? record.start - 1 : markerEnd;
    return TextSelection.collapsed(offset: target, affinity: sel.affinity);
  }

  // The image block containing [offset], or null. Reads paragraph metadata only,
  // so it does not depend on a layout having happened.
  ImageRun? imageRunAt(int offset) {
    final paragraphs = document.paragraphs;
    final i = paragraphs.indexAt(offset);
    final run = paragraphs.imageRunAround(i);
    if (run == null) return null;
    final first = paragraphs.recordAt(run.first);
    final last = paragraphs.recordAt(run.last);
    final level = first.headerLevel!;
    return ImageRun(
      start: first.start,
      end: last.end,
      rows: run.last - run.first + 1,
      level: level,
      id: imageIdOf(level) ?? '',
    );
  }

  /// Every image block of the document, in order (a viewer pages through them).
  List<ImageRun> get imageRuns {
    final records = document.paragraphs.records;
    final runs = <ImageRun>[];
    var i = 0;
    while (i < records.length) {
      if (isImageLevel(records[i].headerLevel)) {
        final run = imageRunAt(records[i].start);
        if (run != null) {
          runs.add(run);
          i += run.rows;
          continue;
        }
      }
      i++;
    }
    return runs;
  }

  /// The image block whose rows carry exactly [level], or null (it may have been
  /// deleted since). Used to find an imported picture's placeholder again.
  ImageRun? imageRunByLevel(String level) {
    final records = document.paragraphs.records;
    for (var i = 0; i < records.length; i++) {
      if (records[i].headerLevel == level) return imageRunAt(records[i].start);
    }
    return null;
  }

  /// Removes an image block without moving the caret away from what it was on
  /// (an imported picture that could not be fetched).
  void discardImage(ImageRun run) {
    final old = selection;
    final before = document.length;
    final a = _deleteImageRun(run).start;
    final removed = before - document.length;
    int map(int o) => o <= a ? o : (o >= a + removed ? o - removed : a);
    if (old.isValid) selection = TextSelection(baseOffset: map(old.baseOffset), extentOffset: map(old.extentOffset));
  }

  /// The image block the selection is inside (caret on one of its rows, or a
  /// selection within it), or null.
  ImageRun? get selectedImageRun {
    final s = selection;
    if (!s.isValid) return null;
    final run = imageRunAt(s.start);
    if (run == null || s.end > run.end) return null;
    return run;
  }

  /// Removes a whole image block (one undo step). The picture's bytes stay in
  /// the store so that undo can bring it back.
  void deleteImage(ImageRun run) {
    selection = _deleteImageRun(run);
  }

  TextSelection _deleteImageRun(ImageRun run) {
    final length = document.length;
    if (run.start > 0) {
      // Take the line breaks from just before the first row through the last
      // row: the line above absorbs the (empty) rows and keeps its own kind, and
      // what follows is untouched.
      final a = run.start - 1;
      commands.dispatch(ReplaceRangeCommand(start: a, end: run.end, text: ''));
      return TextSelection.collapsed(offset: clampInt(a, 0, document.length));
    }
    // The picture opens the note: the rows and their breaks go; if nothing is
    // left after it, the one remaining line must not stay a picture row.
    final end = run.end < length ? run.end + 1 : run.end;
    final cmds = <EditorCommand>[
      ReplaceRangeCommand(start: 0, end: end, text: ''),
      if (run.end >= length) SetHeaderLevelCommand(const EditorSelection.collapsed(0), null),
    ];
    commands.dispatch(cmds.length == 1 ? cmds.first : CompositeCommand(cmds));
    return const TextSelection.collapsed(offset: 0);
  }

  // The part of [set value] that protects image blocks. Returns the selection to
  // settle on when the edit was handled here, or null to let it through.
  TextSelection? _guardImageEdit(TextDiff diff) {
    final paragraphs = document.paragraphs;
    final old = selection;
    final insertion = diff.insertedText.isNotEmpty;

    // The caret (or selection) is on a picture.
    if (old.isValid) {
      final run = imageRunAt(old.start);
      if (run != null && old.end <= run.end) {
        if (insertion) {
          // Typing, Enter or a paste while a picture is selected goes on a new
          // ordinary line: above it when the caret is in the picture's upper
          // half (a tap near its top), below it otherwise.
          final rowIndex = old.start - run.start; // every row is one empty line
          if (rowIndex * 2 < run.rows) {
            final text = diff.insertedText == '\n' ? '\n' : '${diff.insertedText}\n';
            final t = run.start;
            // The insert splits the first row: the new line takes its level and the
            // old row is left plain, so put each back.
            commands.dispatch(CompositeCommand([
              ReplaceRangeCommand(start: t, end: t, text: text, attributesForInsertion: const {}),
              SetHeaderLevelCommand(EditorSelection.collapsed(t), null),
              SetHeaderLevelCommand(EditorSelection.collapsed(t + text.length), run.level),
            ]));
            return TextSelection.collapsed(offset: diff.insertedText == '\n' ? t : t + diff.insertedText.length);
          }
          final t = run.end;
          commands.dispatch(ReplaceRangeCommand(start: t, end: t, text: '\n${diff.insertedText}', attributesForInsertion: const {}));
          return TextSelection.collapsed(offset: t + 1 + diff.insertedText.length);
        }
        return _deleteImageRun(run); // Backspace / Delete removes the whole picture
      }
    }

    // A single line break removed right next to a picture would join a text
    // line into its rows.
    if (!insertion && diff.end == diff.start + 1 && document.text.codeUnitAt(diff.start) == 0x0A) {
      final i = paragraphs.indexAt(diff.start);
      if (i >= 0 && i + 1 < paragraphs.length) {
        final above = paragraphs.recordAt(i);
        final below = paragraphs.recordAt(i + 1);
        if (isImageLevel(above.headerLevel) && !isImageLevel(below.headerLevel)) {
          // Backspace at the start of the line under a picture: an empty line
          // simply goes; otherwise the caret steps into the picture (a second
          // Backspace removes it).
          if (below.start == below.end) return null;
          return TextSelection.collapsed(offset: above.end);
        }
        if (!isImageLevel(above.headerLevel) && isImageLevel(below.headerLevel)) {
          return old.isValid ? old : TextSelection.collapsed(offset: above.end); // Delete at the end of the line above
        }
      }
    }
    return null;
  }

  // Programmatic edits (toolbar, shortcuts, paste) must not write into a picture
  // either: step out to a fresh line below it first.
  void _leaveImageRun() {
    final sel = selection;
    if (!sel.isValid) return;
    final run = imageRunAt(sel.start);
    if (run == null || sel.end > run.end) return;
    commands.dispatch(ReplaceRangeCommand(start: run.end, end: run.end, text: '\n', attributesForInsertion: const {}));
    selection = TextSelection.collapsed(offset: run.end + 1);
  }

  // After a single-character live keystroke, checks whether it just
  // completed an autolink boundary (space/newline/tab) and, if the token
  // before it is URL-shaped, applies the link attribute via
  // CommandDispatcher.setLink — the same path the manual link dialog
  // uses, so it's its own undo step. Only called for a one-character
  // diff; bulk inserts compute their own autolinks before dispatch
  // instead (see set value's general-insert branch), so a paste's links
  // don't each become a separate undo step.
  //
  // Runs after super.value = ... in set value, not before, so
  // this.selection already equals the final IME-reported selection by
  // the time commands.setLink triggers a notify.
  void _maybeAutolink(TextDiff diff) {
    if (diff.insertedText.isEmpty) return;
    final lastChar = diff.insertedText[diff.insertedText.length - 1];
    if (!isAutolinkBoundary(lastChar)) return;

    _linkAddressBefore(diff.start + diff.insertedText.length - 1);
  }

  // Links the address-shaped word that ends at [boundaryIndex] (where a space, tab or line
  // break now is), if there is one and it is not linked to the same place already.
  void _linkAddressBefore(int boundaryIndex) {
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

  // Assigns newValue, guaranteeing listeners are notified even when
  // newValue == value: TextEditingValue equality doesn't cover
  // formatting (lives in document's AttributeStore), so a pure
  // formatting change would otherwise be silently swallowed by
  // ValueNotifier's inherited setter and leave the TextField showing
  // stale styling.
  void _applyValue(TextEditingValue newValue) {
    final valueActuallyChanged = newValue != value;
    super.value = newValue;
    if (!valueActuallyChanged) {
      notifyListeners();
    }
  }

  // The single TransactionManager commit callback — keeps
  // TextEditingController.value's text in sync with document. Clamps the
  // *existing* selection to the new text length, which is correct for
  // formatting-only changes but not text-content changes; call sites that
  // change content correct the selection afterward via _syncSelection
  // (accepting a double notification for those).
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
    // ignore: invalid_use_of_protected_member
    if (documentMutationNotifier.hasListeners) {
      // ignore: invalid_use_of_visible_for_testing_member
      documentMutationNotifier.notifyListeners();
    }
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

  // The current selection as an EditorSelection, defensively clamped: a
  // freshly constructed TextEditingController starts with
  // selection = TextSelection.collapsed(offset: -1) until the bound
  // TextField is focused, which would otherwise trip EditingEngine's
  // bounds assertion if a programmatic edit is called first.
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

  void insertText(String text) {
    _leaveImageRun();
    _syncSelection(commands.insertText(_currentSelection, text));
  }

  void deleteBackward() =>
      _syncSelection(commands.deleteBackward(_currentSelection));

  void deleteForward() =>
      _syncSelection(commands.deleteForward(_currentSelection));

  /// Deletes the current selection outright. No-op if the selection is
  /// collapsed. Prefer this over `deleteBackward()` at call sites (like
  /// cut) that mean "delete what's selected".
  void deleteSelection() =>
      _syncSelection(commands.deleteSelection(_currentSelection));

  /// Pastes `text` as plain content at the current selection — the
  /// programmatic equivalent of typing it in.
  ///
  /// Any bare URL inside `text` is autolinked immediately, same as
  /// [paste] (the system-clipboard path). `text` is normalized to '\n'
  /// line endings first, since an un-normalized '\r' breaks autolink
  /// detection for the affected line.
  void pasteText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final urls = detectAllUrls(normalized);
    if (urls.isEmpty) {
      _repairAndSync(commands.paste(_currentSelection, normalized));
      return;
    }

    // The non-URL portion still inherits sticky formatting, same as
    // ordinary typing (this isn't a rich external paste bringing its own
    // formatting). AttributeType.link is excluded so a stale sticky link
    // value can't compete with the URLs detected in `text` below.
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
    final parsed = const MarkdownImporter().parse(markdown, images: imageStore != null, maxImages: importedImageLimit);
    _repairAndSync(
      commands.pasteRich(_currentSelection, parsed.text, parsed.attributes),
    );
    resolveImportedImages(parsed.images);
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
    final parsed = const HtmlImporter().parse(html, images: imageStore != null, maxImages: importedImageLimit);
    _repairAndSync(
      commands.pasteRich(_currentSelection, parsed.text, parsed.attributes),
    );
    resolveImportedImages(parsed.images);
  }

  /// Copies the current selection to the system clipboard (and to
  /// [clipboard]'s delegate, if one is set, preserving formatting). See
  /// [ClipboardManager.copy].
  Future<void> copy() async {
    final run = selection.isValid && !selection.isCollapsed ? selectedImageRun : null;
    if (run != null) return _copyPicture(run);
    _pictureClip = null;
    await clipboard.copy(_currentSelection);
  }

  // The picture last copied or cut, as a whole. A picture is N blank rows, which is only
  // N-1 line breaks of text: pasted as text it comes back a row short (and, on a line that
  // is not empty, on the wrong rows), so a paste of this exact clipboard places a block.
  ({String text, String id, int rows})? _pictureClip;

  Future<void> _copyPicture(ImageRun run) async {
    await clipboard.copy(EditorSelection(baseOffset: run.start, extentOffset: run.end));
    _pictureClip = (text: document.text.substring(run.start, run.end), id: run.id, rows: run.rows);
  }

  Future<bool> _pastePictureClip() async {
    final clip = _pictureClip;
    if (clip == null) return false;
    final data = await RichClipboardPlatform.getData();
    final text = data.text?.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text != clip.text) {
      _pictureClip = null;
      return false;
    }
    return insertImageBlock(clip.id, rows: clip.rows) != null;
  }

  /// Copies `[start, end)` with its formatting (a code block keeps being a code
  /// block, with its language, when pasted back) without moving the selection.
  Future<void> copyRange(int start, int end) =>
      clipboard.copy(EditorSelection(baseOffset: start, extentOffset: end));

  /// Copies then deletes the current selection. See [ClipboardManager.cut].
  Future<void> cut() async {
    // A picture is its rows; cutting only the line breaks inside it would leave a
    // shorter picture behind. It goes whole, and a paste brings it back whole.
    final run = selection.isValid && !selection.isCollapsed ? selectedImageRun : null;
    if (run != null) {
      await _copyPicture(run);
      deleteImage(run);
      return;
    }
    _pictureClip = null;
    _syncSelection(await clipboard.cut(_currentSelection));
  }

  /// Pastes at the current selection — rich content if [clipboard] has a
  /// matching delegate entry, otherwise plain text from the system
  /// clipboard. See [ClipboardManager.paste].
  Future<void> paste() async {
    if (imageStore != null && await pasteImageFromClipboard()) return;
    if (await _pastePictureClip()) return;
    _leaveImageRun();
    final result = await clipboard.paste(_currentSelection);
    if (result != null) _repairAndSync(result);
    resolveImportedImages(clipboard.takeImports());
  }

  // Syncs selection, then checks whether the paragraph the paste/import
  // landed in (or the one right after it) is part of a numbered run
  // whose markers are no longer sequential, and repairs it — pasted or
  // imported text can arrive with numbering this editor never generated
  // (a list typed in another app, an inconsistent HTML/Markdown source).
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

  /// Scrolls the field so the end of the selection is on screen, once the layout has
  /// settled (two frames on). The field scrolls to the caret by itself when text is
  /// typed, but not when the selection was changed while another route (a sheet) had
  /// the focus, and a toolbar that comes back with the focus shrinks the field
  /// afterwards: the new text could end up under it.
  void revealCaretSoon() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      binding.addPostFrameCallback((_) {
        if (disposed) return;
        final sel = selection;
        if (!sel.isValid) return;
        focusNode.context?.findAncestorStateOfType<EditableTextState>()?.bringIntoView(sel.extent);
      });
    });
  }

  void toggleBold() => commands.toggleBold(_currentSelection);

  /// Exports the current document as an HTML string. Uses
  /// [EditorDocument.exportAttributes] rather than
  /// [EditorDocument.attributes] directly, since header/alignment/
  /// direction are read from `document.paragraphs`, not the attribute
  /// store.
  String toHtml() =>
      const HtmlExporter().export(document.text, document.exportAttributes());

  /// Exports the current document as a Markdown string. See [toHtml].
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

  /// Tab / Shift+Tab in a code block: two-space indent / outdent of the caret
  /// line or the selected lines. No-op outside a code block.
  void indentCode() => _syncSelection(commands.indentCode(_currentSelection));
  void outdentCode() => _syncSelection(commands.indentCode(_currentSelection, outdent: true));

  /// Whether the paragraph containing the current selection starts with
  /// a literal prefix of `type` — drives the list toolbar buttons'
  /// active state.
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

  /// Ticks or unticks the checklist item the caret is on (what tapping its box does); a line that
  /// is not a checklist item becomes an unchecked one.
  void toggleTaskItem() =>
      _syncSelection(commands.toggleTaskItem(_currentSelection));

  /// The Checklist button: the line(s) become checklist items, or, when they all are already,
  /// plain text again. Never ticks an item.
  void toggleChecklist() =>
      _syncSelection(commands.toggleChecklist(_currentSelection));

  /// Whether the paragraph containing the current selection is a
  /// task-list item, and if so, whether it's checked — `null` if it
  /// isn't a checklist item at all. Drives the checklist toolbar
  /// button/toggle's display state.
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

  /// Smallest inline font size the toolbar offers.
  static const double minInlineFontSize = 8.0;
  static const double _fontSizeStep = 2.0;

  RuledRowMetrics get _rowMetrics =>
      renderer.activeRowMetrics ?? renderer.rowMetrics();

  bool get _isHeaderActive => activeAttributeValue(AttributeType.header) != null;

  /// The largest inline size that actually fits one ruled row at the current
  /// effective text scale — the ceiling the toolbar exposes. Inline sizes
  /// above it render fitted to it, so offering more would be a lie.
  double get maxInlineFontSize => _rowMetrics.maxInlineFontSize(
    weight: isAttributeActive(AttributeType.bold)
        ? FontWeight.bold
        : FontWeight.normal,
    italic: isAttributeActive(AttributeType.italic),
    family: isAttributeActive(AttributeType.code)
        ? renderer.theme.codeFontFamily
        : null,
  );

  /// The font size actually *rendered* at the selection (what the toolbar
  /// should display): the stored `size` attribute (or base size) fitted to
  /// the grid, or the header's own size inside a header paragraph. A stored
  /// size larger than the grid allows — e.g. from an import — is preserved in
  /// the document but reported here at its rendered size.
  double get effectiveFontSize {
    final theme = renderer.theme;
    switch (activeAttributeValue(AttributeType.header)) {
      case 'h1':
        return theme.h1FontSize;
      case 'h2':
        return theme.h2FontSize;
      case 'h3':
        return theme.h3FontSize;
    }
    final stored =
        (activeAttributeValue(AttributeType.size) as num?)?.toDouble() ??
        theme.baseFontSize;
    final max = maxInlineFontSize;
    return stored < max ? stored : max;
  }

  /// Whether an inline size can be changed here: never inside a header
  /// paragraph, whose size is structural (and which ignores inline sizes).
  bool get canChangeFontSize => !_isHeaderActive && !isCodeBlockActive;
  bool get canIncreaseFontSize =>
      canChangeFontSize && effectiveFontSize + 0.5 < maxInlineFontSize;
  bool get canDecreaseFontSize =>
      canChangeFontSize && effectiveFontSize - 0.5 > minInlineFontSize;

  void increaseFontSize() {
    if (!canIncreaseFontSize) return;
    final next = (effectiveFontSize + _fontSizeStep).clamp(
      minInlineFontSize,
      maxInlineFontSize,
    );
    setSize(next);
  }

  void decreaseFontSize() {
    if (!canDecreaseFontSize) return;
    final next = (effectiveFontSize - _fontSizeStep).clamp(
      minInlineFontSize,
      maxInlineFontSize,
    );
    setSize(next);
  }

  // ---------------------------------------------------------------------
  // Code blocks
  // ---------------------------------------------------------------------

  /// The raw block level (`h1`..`h3`, `code`, `code:<lang>` or `null`) every
  /// paragraph of the selection agrees on; `null` if they differ.
  String? get activeBlockLevel {
    final sel = _currentSelection;
    final records = document.paragraphs.recordsOverlapping(sel.start, sel.end);
    if (records.isEmpty) return null;
    final level = records.first.headerLevel;
    return records.every((r) => r.headerLevel == level) ? level : null;
  }

  /// Whether the whole selection (or caret line) is inside a code block.
  bool get isCodeBlockActive => isCodeBlockLevel(activeBlockLevel);

  /// Language label of the code block at the selection, or `null`.
  String? get activeCodeLanguage => codeBlockLanguage(activeBlockLevel);

  /// Turns the selected paragraphs into a code block (optionally labelled),
  /// or back into ordinary paragraphs if they already are one.
  ///
  /// Turning it off applies to the whole block the caret or selection is in,
  /// not just the line the caret happens to be on.
  void toggleCodeBlock({String? language}) {
    if (!isCodeBlockActive) {
      commands.setHeader(_currentSelection, codeBlockLevelFor(language));
      return;
    }
    final sel = _currentSelection;
    final run = _codeBlockRun(sel.start, sel.end);
    commands.setHeader(run == null ? sel : EditorSelection(baseOffset: run.start, extentOffset: run.end), null);
  }

  // The whole code block(s) touched by `[start, end]`: from the first line of
  // the block containing `start` to the last line of the one containing `end`.
  ({int start, int end})? _codeBlockRun(int start, int end) {
    final records = document.paragraphs.records;
    final a = records.indexWhere((r) => r.contains(start));
    final b = records.indexWhere((r) => r.contains(end));
    if (a == -1 || b == -1 || !isCodeBlockLevel(records[a].headerLevel)) return null;
    var first = a;
    var last = b;
    while (first > 0 && isCodeBlockLevel(records[first - 1].headerLevel)) {
      first--;
    }
    while (last < records.length - 1 && isCodeBlockLevel(records[last + 1].headerLevel)) {
      last++;
    }
    return (start: records[first].start, end: records[last].end);
  }

  /// Sets (or clears, with `null`) the language label of the whole code
  /// block containing the caret.
  void setCodeBlockLanguage(String? language) {
    final sel = _currentSelection;
    final run = _codeBlockRun(sel.start, sel.start);
    if (run == null) return;
    commands.setHeader(EditorSelection(baseOffset: run.start, extentOffset: run.end), codeBlockLevelFor(language));
  }

  /// The exact text of the code block spanning `[start, end)` (a
  /// `CodeBlockRegion`'s extent), for a Copy action.
  String codeBlockText(int start, int end) => document.text.substring(start, end);

  void setLink(String? url) => commands.setLink(_currentSelection, url);

  /// Changes the text and/or address of the link at [range] in one undo step;
  /// `url: null` removes the link and keeps its text.
  void editLink(TextRange range, String text, String? url) =>
      _syncSelection(commands.editLink(range.start, range.end, text, url));
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
  /// Header/alignment/text-direction delegate to [activeAttributeValue]
  /// since they're read from [EditorDocument.paragraphs], not
  /// `attributeStore`.
  bool isAttributeActive(AttributeType type) {
    if (type == AttributeType.header ||
        type == AttributeType.align ||
        type == AttributeType.textDirection) {
      return activeAttributeValue(type) != null;
    }
    final sel = _currentSelection;
    if (sel.isCollapsed) {
      return engine.stickyAttributes.containsKey(type) ||
          (!engine.stickyOff.contains(type) && document.attributeStore.findAt(sel.start, type: type).isNotEmpty);
    }
    return document.attributeStore.coversRange(sel.start, sel.end, type);
  }

  /// The active value of a value-carrying attribute (color, size, link,
  /// header) at the current selection, or `null` if not active /
  /// inconsistent across the selection. Drives toolbar value display
  /// (e.g. showing the current color swatch).
  ///
  /// [AttributeType.header] reads from [EditorDocument.paragraphs]
  /// instead of `attributeStore`. "Active" for a multi-paragraph
  /// selection means every paragraph agrees on the same `headerLevel`.
  Object? activeAttributeValue(AttributeType type) {
    if (type == AttributeType.header) {
      final sel = _currentSelection;
      final startRecord = document.paragraphs.paragraphAt(sel.start);
      if (startRecord == null) return null;
      // A code line's block level is not a heading: see [activeBlockLevel].
      String? headingOnly(String? level) => isCodeBlockLevel(level) ? null : level;
      if (sel.isCollapsed) return headingOnly(startRecord.headerLevel);
      final overlapping = document.paragraphs.recordsOverlapping(
        sel.start,
        sel.end,
      );
      if (overlapping.isEmpty) return null;
      final level = overlapping.first.headerLevel;
      final allAgree = overlapping.every((r) => r.headerLevel == level);
      return allAgree ? headingOnly(level) : null;
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
      if (engine.stickyOff.contains(type)) return null;
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
  /// Checks both `offset` and `offset - 1`, since a tap on the right
  /// half of a link's last character produces `offset == link.end`, not
  /// `link.end - 1`. This is inherently ambiguous with a tap intended to
  /// place the caret just after the link — pairing this with a
  /// confirmation dialog before launching (see `RichTextEditor`) is what
  /// makes that harmless.
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
    // ignore: invalid_use_of_protected_member
    if (documentMutationNotifier.hasListeners) {
      // ignore: invalid_use_of_visible_for_testing_member
      documentMutationNotifier.notifyListeners();
    }
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

  /// Jumps directly to the match at `index` into [search]'s `matches`. No-op
  /// if `index` is out of range. See [SearchIndex.selectMatch].
  void findAt(int index) {
    search.selectMatch(index);
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
  /// Notifies unconditionally: the current-match highlight is driven by
  /// `search.currentMatch`, not `value`, so it needs its own explicit
  /// rebuild trigger or it would visibly linger after the find bar
  /// closes.
  void clearFind() {
    search.clear();
    notifyListeners();
  }

  void _selectCurrentMatch() {
    final match = search.currentMatch;
    if (match == null) {
      // Still notify, or a previous search's highlight would stay stuck
      // on screen (same reasoning as clearFind).
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

  // Converted from search.matches to the TextRanges renderSpan wants,
  // memoized by reference to the source list — renderSpan's own cache
  // compares allMatchesRanges by identical(), so recomputing a fresh list
  // every call would defeat that cache on every keystroke.
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
    final textScaler = MediaQuery.textScalerOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    // The row grid of the *real* render (merged TextField style), so the
    // toolbar's font-size limits always describe what is on screen.
    renderer.activeRowMetrics = renderer.rowMetrics(
      textScaler: textScaler,
      devicePixelRatio: devicePixelRatio,
      style: style,
    );
    final span = renderer.renderSpan(
      document,
      style: style,
      composingRange: withComposing ? value.composing : null,
      matchHighlightRange: match != null
          ? TextRange(start: match.start, end: match.end)
          : null,
      selectionHighlightRange: _selectionHighlight,
      allMatchesRanges: _currentAllMatchesRanges,
      // Must match the scaler `RichTextEditor` measures ruled lines
      // against (its own `MediaQuery.textScalerOf(context)`) — this is
      // the same ambient value, read from the context RenderEditable
      // hands buildTextSpan.
      textScaler: textScaler,
      devicePixelRatio: devicePixelRatio,
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
