import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';
import 'editor_document.dart';
import 'editor_selection.dart';
import 'paragraph_record.dart';
import 'transaction_manager.dart';

/// All editing logic for an [EditorDocument]: insert, delete, replace,
/// toggle/apply/remove formatting, paste and rich paste, clear
/// formatting — every operation the old `RichTextEditingController` did
/// by hand-rolling text and span math inline.
///
/// [EditingEngine] talks to the document only through [EditorDocument]'s
/// [TextBuffer], [AttributeStore], and `ParagraphIndex` — it never
/// touches a raw `String`. It's also undo-agnostic on purpose: it
/// doesn't know a `HistoryManager` exists. Recording undo deltas is a
/// wrapping concern that belongs to the Command layer, not something
/// every editing method here should have to remember to do.
///
/// Every mutating method calls [TransactionManager.notify] exactly once
/// for its own edit. Callers composing several calls into one logical
/// operation (paste, bulk formatting, etc.) should wrap them in
/// `transactions.run(() { ... })` so the surrounding UI only rebuilds
/// once — see [TransactionManager].
class EditingEngine {
  final EditorDocument document;
  final TransactionManager transactions;

  /// Formatting that will be applied to the *next* inserted text when
  /// the selection is collapsed — e.g. the user tapped "bold" with
  /// nothing selected, and wants the next characters they type to come
  /// out bold. Keyed by attribute type; the value is `null` for toggle
  /// attributes and the payload (color, size, link) for value attributes.
  final Map<AttributeType, Object?> _stickyAttributes = {};

  EditingEngine({required this.document, required this.transactions});

  /// Read-only view of the formatting pending for the next typed
  /// character(s) at a collapsed cursor.
  Map<AttributeType, Object?> get stickyAttributes =>
      Map.unmodifiable(_stickyAttributes);

  /// Recomputes sticky formatting from what's already applied at
  /// `position`, for when the cursor moves without a text change (the
  /// caret landing inside bold text should show "bold" as active). Call
  /// this from the controller on selection-only changes.
  void syncStickyAttributesAt(int position) {
    _stickyAttributes.clear();
    if (position < 0 || position >= document.length) return;
    for (final attr in document.attributeStore.findAt(position)) {
      _stickyAttributes[attr.type] = attr.value;
    }
  }

  // ---------------------------------------------------------------------
  // Primitive edit
  // ---------------------------------------------------------------------

  /// Replaces `[start, end)` with `text`, shifting and clamping spans to
  /// match, and notifying once. Every other editing method reduces to
  /// this.
  ///
  /// The inserted text is formatted with `attributesForInsertion` if
  /// given, otherwise the live [stickyAttributes]. Commands (Phase 3)
  /// always pass `attributesForInsertion` explicitly — pinning the exact
  /// attributes at the moment of the edit, rather than reading whatever
  /// sticky state happens to be live later — so that redo reproduces the
  /// original edit exactly even if the user has toggled other formatting
  /// in between.
  EditorSelection replaceRange(
      int start,
      int end,
      String text, {
        Map<AttributeType, Object?>? attributesForInsertion,
      }) {
    assert(start >= 0 && end <= document.length && start <= end,
    'replaceRange range out of bounds');

    final buffer = document.buffer;
    final store = document.attributeStore;

    if (end > start) {
      store.shiftForDeletion(start, end);
      buffer.delete(start, end);
      document.paragraphs.applyDeletion(start, end);
    }

    if (text.isNotEmpty) {
      store.shiftForInsertion(start, text.length);
      buffer.insert(start, text);
      document.paragraphs.applyInsertion(start, text);

      final insertionAttributes = attributesForInsertion ?? _stickyAttributes;
      for (final entry in insertionAttributes.entries) {
        store.insert(TextAttribute(
          start: start,
          end: start + text.length,
          type: entry.key,
          value: entry.value,
        ));
      }
      for (final type in insertionAttributes.keys) {
        store.optimize(type: type);
      }

      if (text.contains('\n')) {
        _confineParagraphScopedAttributes(start, start + text.length);
      }
    }

    assert(_debugValidateParagraphs());
    transactions.notify();
    return EditorSelection.collapsed(start + text.length);
  }

  /// Debug-only: asserts `ParagraphIndex` remains internally well-formed
  /// (contiguous, gap-free, spanning the whole document) after a
  /// mutation.
  ///
  /// This is what's left of the Phase 2 dual-write consistency check,
  /// now that header no longer lives in `AttributeStore` at all going
  /// forward — comparing the two would produce *expected*, correct
  /// disagreement the moment anyone uses `setHeaderLevel`, not a bug to
  /// catch. The structural invariant itself is still worth checking on
  /// every edit, same as before; see [ParagraphIndex.debugValidate].
  ///
  /// Wrapped in `assert(...)` at every call site so it's compiled out
  /// entirely in release builds.
  bool _debugValidateParagraphs() {
    document.paragraphs.debugValidate(document.text.length);
    return true;
  }

  /// Trims paragraph-scoped attributes to the paragraph they started in
  /// after a newline insertion.
  ///
  /// [AttributeType.link] and [AttributeType.code] are confined to the
  /// paragraph they started in (cut off before the newline) — a span
  /// that used to run through what is now a paragraph break gets
  /// truncated at the break instead of silently spanning two paragraphs.
  /// [AttributeType.header] used to be handled here too; it's gone from
  /// this check because it's gone from `AttributeStore` entirely —
  /// header confinement is now `ParagraphIndex.applyInsertion`'s split
  /// logic (only the first fragment keeps `headerLevel`), which this
  /// method has nothing to do with anymore. See the block-architecture
  /// design notes.
  ///
  /// Bullet/numbered lists used to be handled here too, continuing the
  /// list attribute onto the next paragraph. That branch is gone — see
  /// the removal notes on [AttributeType] for why: it dropped list
  /// formatting on every paragraph beyond the one immediately following
  /// a break (a single span can cover many list items, but this method
  /// only ever re-inserted two fragments — the paragraph before the
  /// break and the one immediately after), and its per-newline call to
  /// a paragraph-bounds scan — itself an O(document length) scan —
  /// turned every newline in an inserted/pasted range into another
  /// full-text scan, i.e. O(newlines × document length) for a single
  /// paste. A large imported note with many list items would hang on
  /// that alone.
  void _confineParagraphScopedAttributes(int rangeStart, int rangeEnd) {
    final text = document.text;
    final store = document.attributeStore;
    final end = rangeEnd < text.length ? rangeEnd : text.length;

    for (var i = rangeStart; i < end; i++) {
      if (text.codeUnitAt(i) != 0x0A) continue; // Newline at index i

      final intersecting = store.findIntersecting(i, i + 1);
      for (final span in intersecting) {
        final type = span.type;
        final isConfined = type == AttributeType.link || type == AttributeType.code;
        if (!isConfined) continue;

        store.remove(span);
        if (span.start < i) {
          store.insert(span.copyWith(end: i));
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // Selection-aware editing
  // ---------------------------------------------------------------------

  /// Inserts `text`, replacing `selection` if it isn't collapsed — the
  /// same behavior a `TextField` gives you for free, made explicit here
  /// so it can be driven by commands/tests without a widget.
  EditorSelection insert(EditorSelection selection, String text) {
    return replaceRange(selection.start, selection.end, text);
  }

  /// Deletes `selection` if it isn't collapsed; no-ops if it is. Use
  /// [deleteBackward]/[deleteForward] for a collapsed caret.
  EditorSelection deleteRange(EditorSelection selection) {
    if (selection.isCollapsed) return selection;
    return replaceRange(selection.start, selection.end, '');
  }

  /// Backspace: deletes `selection`, or the one character before a
  /// collapsed caret. Thin mutating wrapper around [deleteBackwardEdit]
  /// — see that method for the actual logic (smart list-marker removal,
  /// numbered-list renumbering). Kept as a real method (not inlined)
  /// since it's the natural "just do it" entry point for any direct
  /// caller; [deleteBackwardEdit] exists for callers that need to
  /// dispatch the edit through a Command instead of applying it
  /// directly — `CommandDispatcher.deleteBackward` and
  /// `RichEditorController.set value`'s live-backspace detection both
  /// use that one, not this one.
  ///
  /// Note: this deletes one UTF-16 code unit, same granularity as the
  /// original controller, for the plain (non-list) case. It does not
  /// currently combine surrogate pairs or grapheme clusters (emoji,
  /// combining marks) into a single delete — worth revisiting with the
  /// `characters` package if that surfaces as a real bug, but it wasn't
  /// handled before either, so this isn't a regression.
  EditorSelection deleteBackward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteRange(selection);
    final edit = deleteBackwardEdit(selection);
    if (edit == null) return selection;
    replaceRange(edit.start, edit.end, edit.text);
    return EditorSelection.collapsed(edit.start + edit.cursorOffsetFromStart);
  }

  /// Computes the edit for a backspace at a collapsed `selection` —
  /// pure computation, mutates nothing, mirrors [enterKeyEditWithRenumber]'s
  /// pattern exactly. Returns `null` for a non-collapsed `selection` (use
  /// [deleteRange] instead) or a caret already at document start (nothing
  /// to delete).
  ///
  /// This is the single, consolidated backspace-computation path,
  /// replacing what used to be two independently-drifting copies of
  /// similar logic: [deleteBackward] itself (only reachable if called
  /// directly — `CommandDispatcher.deleteBackward` turned out to bypass
  /// it entirely with its own hardcoded single-character deletion) and
  /// `RichEditorController.set value`'s separate ad hoc check for live
  /// typing. Both now call this instead of maintaining their own logic.
  ///
  /// Three cases at the caret:
  /// 1. Right after a paragraph's list prefix (right at the start of
  ///    the item's own text): removes the whole prefix in one step —
  ///    see [deleteBackward]'s doc comment on why the prefix stays real,
  ///    individually-deletable text rather than a true protected unit.
  ///    If that paragraph was part of a numbered run, also renumbers
  ///    everything after it down by one — see [_removeListMarkerEdit].
  /// 2. Otherwise: the plain single-character deletion.
  ///
  /// Renumbering is one atomic combined replacement computed entirely
  /// from the current, unmutated document — not a multi-step composite,
  /// same reasoning as [enterKeyEditWithRenumber]. `ParagraphIndex`
  /// itself is never touched to compute it or asked to touch the text:
  /// this reads `document.paragraphs.records` (an O(paragraphs)
  /// traversal, not a full-text scan) and rewrites digits using
  /// bounded, per-paragraph [listPrefixLength] checks — the same
  /// derived-from-text approach used everywhere else list-ness is
  /// checked in this codebase, not stored metadata that could drift
  /// from what's actually typed.
  ({int start, int end, String text, int cursorOffsetFromStart})? deleteBackwardEdit(
      EditorSelection selection,
      ) {
    if (!selection.isCollapsed) return null;
    if (selection.start == 0) return null;

    final text = document.text;
    final record = document.paragraphs.paragraphAt(selection.start);

    if (record != null) {
      final prefixLen = listPrefixLength(text, record.start);
      if (prefixLen > 0 && selection.start == record.start + prefixLen) {
        return _removeListMarkerEdit(record, prefixLen);
      }
    }

    return (start: selection.start - 1, end: selection.start, text: '', cursorOffsetFromStart: 0);
  }

  /// The list-marker-removal half of [deleteBackwardEdit] — split out
  /// for readability. `record` is the paragraph the caret's prefix
  /// belongs to; `prefixLen` is that prefix's length (already confirmed
  /// non-zero and matching the caret position by the caller).
  ///
  /// A bullet (or a numbered item with nothing numbered after it in the
  /// same run) just has its prefix removed — the plain case. A numbered
  /// item with more numbered items following renumbers all of them down
  /// by one, computed as a single combined replacement spanning from
  /// this paragraph's start to the end of the affected run — hand-traced
  /// against a concrete example while designing this, same discipline
  /// as [enterKeyEditWithRenumber].
  ({int start, int end, String text, int cursorOffsetFromStart}) _removeListMarkerEdit(
      ParagraphRecord record,
      int prefixLen,
      ) {
    final text = document.text;
    final prefix = text.substring(record.start, record.start + prefixLen);
    final ownContent = text.substring(record.start + prefixLen, record.end);
    final plain = (
    start: record.start,
    end: record.start + prefixLen,
    text: '',
    cursorOffsetFromStart: 0,
    );

    if (listTypeOfPrefix(prefix) != ParagraphListType.numbered) return plain;

    final indent = RegExp(r'^[ \t]*').firstMatch(prefix)!.group(0)!;
    final records = document.paragraphs.records;
    final currentIndex = records.indexOf(record);
    if (currentIndex == -1) return plain;

    bool matchesRun(int i) {
      if (i < 0 || i >= records.length) return false;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      if (len == 0) return false;
      final p = text.substring(r.start, r.start + len);
      return listTypeOfPrefix(p) == ParagraphListType.numbered &&
          RegExp(r'^[ \t]*').firstMatch(p)!.group(0)! == indent;
    }

    if (!matchesRun(currentIndex + 1)) return plain; // nothing after to renumber

    var lastIndex = currentIndex + 1;
    while (matchesRun(lastIndex + 1)) {
      lastIndex++;
    }

    final buffer = StringBuffer(ownContent);
    var number = 0;
    for (var i = currentIndex + 1; i <= lastIndex; i++) {
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final content = text.substring(r.start + len, r.end);
      buffer.write('\n$indent$number. $content');
    }

    return (
    start: record.start,
    end: records[lastIndex].end,
    text: buffer.toString(),
    cursorOffsetFromStart: ownContent.length,
    );
  }

  /// Forward delete: deletes `selection`, or the one character after a
  /// collapsed caret. Same code-unit-granularity caveat as
  /// [deleteBackward].
  EditorSelection deleteForward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteRange(selection);
    if (selection.start >= document.length) return selection;
    return replaceRange(selection.start, selection.start + 1, '');
  }

  // ---------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------

  /// The range an [applyAttribute]/[removeAttribute] call for `type`
  /// will actually affect. Always just `selection` now — no remaining
  /// `AttributeType` is paragraph-scoped, since header (the only one
  /// that ever was) has its own dedicated [setHeaderLevel] path instead.
  /// Kept as a real method, not deleted, because `ApplyAttributeCommand`
  /// still calls it for color/size/link — the `type` parameter is
  /// unused now but stays in the signature for that reason.
  EditorSelection effectiveRangeFor(AttributeType type, EditorSelection selection) {
    return selection;
  }

  /// The paragraph(s) `selection` would expand to for header purposes —
  /// a selection spanning multiple paragraphs affects all of them, same
  /// as the old `_paragraphBounds`-based behavior. Unlike that method,
  /// this is a direct [ParagraphIndex.paragraphAt] lookup rather than an
  /// O(document length) `text.lastIndexOf`/`indexOf` scan — the one
  /// concrete performance win this migration was motivated by, actually
  /// landing here. Exposed publicly so [SetHeaderLevelCommand] can
  /// compute the exact same range to snapshot for undo.
  EditorSelection headerBoundsFor(EditorSelection selection) {
    final startRecord = document.paragraphs.paragraphAt(selection.start);
    final endRecord = document.paragraphs.paragraphAt(selection.end);
    final rangeStart = startRecord?.start ?? selection.start;
    final rangeEnd = endRecord?.end ?? selection.end;
    return EditorSelection(baseOffset: rangeStart, extentOffset: rangeEnd);
  }

  /// Sets `headerLevel` on the paragraph(s) containing `selection` —
  /// header's entire live representation now; `AttributeType.header` is
  /// no longer written to anywhere in this class. See
  /// `ParagraphIndex.setHeaderLevel`'s own doc comment and the
  /// block-architecture design notes for the full history. Driven by
  /// [SetHeaderLevelCommand], not [applyAttribute] — header no longer
  /// goes through the generic attribute path at all.
  void setHeaderLevel(EditorSelection selection, String? headerLevel) {
    final range = headerBoundsFor(selection);
    document.paragraphs.setHeaderLevel(range.start, range.end, headerLevel);
    assert(_debugValidateParagraphs());
    transactions.notify();
  }

  /// Computes the replacement for a live Enter keypress at `selection`:
  /// list continuation as literal text.
  ///
  /// If the paragraph containing the caret begins with a literal
  /// list-style prefix (`'- '`, `'* '`, `'+ '`, or `'N. '`), pressing
  /// Enter continues the list onto the new line by repeating the prefix
  /// (numbered prefixes increment). Pressing Enter on a list item that's
  /// empty except for its prefix exits the list instead — the prefix is
  /// removed rather than repeated indefinitely, matching the usual
  /// "empty bullet + Enter" convention.
  ///
  /// This only ever produces literal text to insert in place of a bare
  /// `'\n'` — there's no [AttributeType] involved and nothing here
  /// touches the render layer, so unlike the old marker-based lists it
  /// can never desync `RenderEditable`'s caret math from the document.
  /// Callers should dispatch the returned `(start, end, text)` as a
  /// single replace so it undoes as one step.
  ///
  /// Not applied when `selection` isn't collapsed — replacing a real
  /// selection with Enter just inserts a plain newline, same as before.
  ({int start, int end, String text}) enterKeyEdit(EditorSelection selection) {
    if (!selection.isCollapsed) {
      return (start: selection.start, end: selection.end, text: '\n');
    }

    final text = document.text;
    final caret = selection.start;

    final prevNewline = caret <= 0 ? -1 : text.lastIndexOf('\n', caret - 1);
    final paragraphStart = prevNewline == -1 ? 0 : prevNewline + 1;
    final nextNewline = text.indexOf('\n', caret);
    final paragraphEnd = nextNewline == -1 ? text.length : nextNewline;

    final beforeCaret = text.substring(paragraphStart, caret);
    final match = listPrefixPattern.matchAsPrefix(beforeCaret);
    if (match == null) {
      return (start: caret, end: caret, text: '\n');
    }

    final prefix = match.group(0)!;
    final restBeforeCaret = beforeCaret.substring(prefix.length).trim();
    final restAfterCaret = text.substring(caret, paragraphEnd).trim();

    if (restBeforeCaret.isEmpty && restAfterCaret.isEmpty) {
      // Empty list item: exit the list instead of repeating the prefix.
      return (start: paragraphStart, end: caret, text: '\n');
    }

    return (start: caret, end: caret, text: '\n${nextListPrefix(prefix)}');
  }

  /// Extends [enterKeyEdit]: if the computed continuation starts a
  /// fresh *numbered* item, also renumbers every subsequent paragraph in
  /// the same contiguous numbered run so the whole list stays in
  /// sequence — whether the split happens at the end of the line (the
  /// new item is empty) or in the middle of it (the new item gets
  /// whatever text was after the caret, and everything after *that*
  /// shifts up by one).
  ///
  /// Computed as one combined replacement — from the caret to the end
  /// of the affected run — built entirely from the current, unmutated
  /// document. Deliberately not a multi-step composite: sequencing
  /// several separate edits so each one's offsets stay valid against
  /// the ones before it is exactly the kind of arithmetic that's caused
  /// real bugs earlier in this codebase's history, and there's a
  /// simpler alternative here — the final text is fully knowable in
  /// advance, so it can just be computed once, upfront.
  ///
  /// Returns the same shape as [enterKeyEdit] plus `cursorOffsetFromStart`
  /// — callers must use `start + cursorOffsetFromStart` for the
  /// resulting caret position, not `start + text.length`: `text` may
  /// include the rewritten trailing items, but the caret always belongs
  /// right after the *new* item's own prefix, not at the end of
  /// everything that got renumbered.
  ({int start, int end, String text, int cursorOffsetFromStart}) enterKeyEditWithRenumber(
      EditorSelection selection,
      ) {
    final base = enterKeyEdit(selection);
    final plain = (start: base.start, end: base.end, text: base.text, cursorOffsetFromStart: base.text.length);

    if (base.text == '\n') return plain; // exit-list or plain newline — nothing to renumber
    final insertedPrefix = base.text.substring(1);
    if (listTypeOfPrefix(insertedPrefix) != ParagraphListType.numbered) return plain;

    final caret = selection.start;
    if (base.start != caret || base.end != caret) return plain; // only the pure-insert "continue" case
    final currentRecord = document.paragraphs.paragraphAt(caret);
    if (currentRecord == null) return plain;

    final text = document.text;
    final records = document.paragraphs.records;
    final currentIndex = records.indexOf(currentRecord);
    if (currentIndex == -1) return plain;

    final numberedMatch = RegExp(r'^([ \t]*)(\d+)\. $').firstMatch(insertedPrefix)!;
    final indent = numberedMatch.group(1)!;

    bool matchesRun(int i) {
      if (i < 0 || i >= records.length) return false;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      if (len == 0) return false;
      final prefix = text.substring(r.start, r.start + len);
      return listTypeOfPrefix(prefix) == ParagraphListType.numbered &&
          RegExp(r'^[ \t]*').firstMatch(prefix)!.group(0)! == indent;
    }

    // Whatever was after the caret on the current line (empty for an
    // end-of-line Enter, the rest of the line for a mid-line split) —
    // this becomes the new item's own content, exactly as a plain Enter
    // would leave it in place, just now folded into the same combined
    // replacement as the renumbering.
    final tailContent = text.substring(caret, currentRecord.end);

    if (!matchesRun(currentIndex + 1) && tailContent.isEmpty) {
      // Nothing after to renumber, and nothing left on this line either
      // — the plain single-item continuation is already correct.
      return plain;
    }

    var lastIndex = currentIndex;
    while (matchesRun(lastIndex + 1)) {
      lastIndex++;
    }

    var number = int.parse(numberedMatch.group(2)!);
    final buffer = StringBuffer('\n$indent$number. $tailContent');
    for (var i = currentIndex + 1; i <= lastIndex; i++) {
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final content = text.substring(r.start + len, r.end);
      buffer.write('\n$indent$number. $content');
    }

    return (
    start: caret,
    end: lastIndex > currentIndex ? records[lastIndex].end : currentRecord.end,
    text: buffer.toString(),
    cursorOffsetFromStart: base.text.length,
    );
  }

  /// Toggles a paragraph (or, for a real selection, every paragraph the
  /// selection spans) between having a list prefix of `type` and not —
  /// as one atomic text replacement, computed entirely from the current
  /// document with no intermediate mutation, so this is safe without
  /// needing a composite/batched command.
  ///
  /// Bullets have no sequence to keep consistent, so toggling one only
  /// ever touches the selected range itself. Numbered lists are
  /// different: turning a paragraph on or off can join it to, or split
  /// it out of, a run of numbered items *outside* the selection — see
  /// [_numberedToggleEdit] for why this can't just treat the selected
  /// range in isolation the way bullets can.
  ///
  /// Whether this turns the list *on* or *off*: off only if *every*
  /// paragraph in range already has this exact type; on if any of them
  /// doesn't. A mixed selection (some list items, some plain paragraphs)
  /// becomes a list entirely, rather than being decided by whichever
  /// paragraph happens to be first — matches standard editor behavior
  /// for a mixed selection, and is a deliberate difference from
  /// `EditingEngine.toggleAttribute`'s "first paragraph decides"
  /// convention for *inline* formatting, which doesn't have this
  /// "mixed selection" ambiguity in the same way (a partially-bold
  /// selection becoming fully bold is the same "any gap turns it on"
  /// rule, just phrased per-character instead of per-paragraph).
  ({int start, int end, String text})? listToggleEdit(EditorSelection selection, ParagraphListType type) {
    final text = document.text;
    final records = document.paragraphs.records;
    final startRecord = document.paragraphs.paragraphAt(selection.start);
    if (startRecord == null) return null;
    final endRecord = document.paragraphs.paragraphAt(selection.end) ?? startRecord;
    final startIndex = records.indexOf(startRecord);
    final endIndex = records.indexOf(endRecord);
    if (startIndex == -1 || endIndex == -1) return null;

    var allAlreadyType = true;
    for (var i = startIndex; i <= endIndex; i++) {
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final t = len > 0 ? listTypeOfPrefix(text.substring(r.start, r.start + len)) : null;
      if (t != type) {
        allAlreadyType = false;
        break;
      }
    }
    final turningOn = !allAlreadyType;

    if (type == ParagraphListType.bullet) {
      final buffer = StringBuffer();
      for (var i = startIndex; i <= endIndex; i++) {
        if (i > startIndex) buffer.write('\n');
        final r = records[i];
        final prefixLen = listPrefixLength(text, r.start);
        final content = text.substring(r.start + prefixLen, r.end);
        // The '  ' default indent on a fresh toggle-on (rather than
        // flush-left) is deliberate: a bare '- ' reads as "just a
        // dash", not as a list — real editors give a list item some
        // breathing room by default.
        if (turningOn) buffer.write('  - ');
        buffer.write(content);
      }
      return (start: startRecord.start, end: endRecord.end, text: buffer.toString());
    }

    return _numberedToggleEdit(text, records, startIndex, endIndex, turningOn);
  }

  /// The numbered half of [listToggleEdit] — split out because it has
  /// to consider paragraphs *outside* [startIndex, endIndex] that
  /// [listToggleEdit] itself never touches directly.
  ///
  /// Turning on: this may be resuming a numbered run that continues
  /// immediately before or after the selection — the paragraph(s) being
  /// toggled don't necessarily know their own correct number in
  /// isolation. The whole contiguous run (selection plus whatever
  /// matching-indent numbered paragraphs border it) gets renumbered
  /// together, 1..N.
  ///
  /// Turning off: removing list-ness from the middle of a run splits it
  /// into a "before" and "after" segment — they're two separate lists
  /// once the de-listed paragraphs are between them, so each is
  /// renumbered independently starting back at 1, not continuing as if
  /// nothing changed.
  ({int start, int end, String text}) _numberedToggleEdit(
      String text,
      List<ParagraphRecord> records,
      int startIndex,
      int endIndex,
      bool turningOn,
      ) {
    String indentOf(int i) {
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      if (len == 0) return '  ';
      final prefix = text.substring(r.start, r.start + len);
      final ws = RegExp(r'^[ \t]*').firstMatch(prefix)!.group(0)!;
      return ws.isEmpty ? '  ' : ws;
    }

    bool matchesNumberedIndent(int i, String indent) {
      if (i < 0 || i >= records.length) return false;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      if (len == 0) return false;
      final p = text.substring(r.start, r.start + len);
      return listTypeOfPrefix(p) == ParagraphListType.numbered &&
          RegExp(r'^[ \t]*').firstMatch(p)!.group(0)! == indent;
    }

    if (turningOn) {
      // Prefer an adjacent existing numbered run's indent over this
      // paragraph's own — it may have no prefix at all yet (or a
      // bullet's), neither of which should override "resume the list
      // this item is rejoining". Only fall back to its own indent (or
      // the default) if neither neighbor is already part of one.
      String? adjacentIndent;
      if (startIndex > 0) {
        final len = listPrefixLength(text, records[startIndex - 1].start);
        if (len > 0) {
          final p = text.substring(records[startIndex - 1].start, records[startIndex - 1].start + len);
          if (listTypeOfPrefix(p) == ParagraphListType.numbered) {
            adjacentIndent = RegExp(r'^[ \t]*').firstMatch(p)!.group(0)!;
          }
        }
      }
      if (adjacentIndent == null && endIndex < records.length - 1) {
        final len = listPrefixLength(text, records[endIndex + 1].start);
        if (len > 0) {
          final p = text.substring(records[endIndex + 1].start, records[endIndex + 1].start + len);
          if (listTypeOfPrefix(p) == ParagraphListType.numbered) {
            adjacentIndent = RegExp(r'^[ \t]*').firstMatch(p)!.group(0)!;
          }
        }
      }
      final indent = adjacentIndent ?? indentOf(startIndex);

      var runStart = startIndex;
      while (runStart > 0 && matchesNumberedIndent(runStart - 1, indent)) {
        runStart--;
      }
      var runEnd = endIndex;
      while (runEnd < records.length - 1 && matchesNumberedIndent(runEnd + 1, indent)) {
        runEnd++;
      }

      final buffer = StringBuffer();
      var number = 0;
      for (var i = runStart; i <= runEnd; i++) {
        if (i > runStart) buffer.write('\n');
        number++;
        final r = records[i];
        final len = listPrefixLength(text, r.start);
        final content = text.substring(r.start + len, r.end);
        buffer.write('$indent$number. $content');
      }
      return (start: records[runStart].start, end: records[runEnd].end, text: buffer.toString());
    }

    // Turning off.
    final indent = indentOf(startIndex);
    var beforeStart = startIndex;
    while (beforeStart > 0 && matchesNumberedIndent(beforeStart - 1, indent)) {
      beforeStart--;
    }
    var afterEnd = endIndex;
    while (afterEnd < records.length - 1 && matchesNumberedIndent(afterEnd + 1, indent)) {
      afterEnd++;
    }

    final buffer = StringBuffer();
    var number = 0;
    for (var i = beforeStart; i < startIndex; i++) {
      if (i > beforeStart) buffer.write('\n');
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      buffer.write('$indent$number. ${text.substring(r.start + len, r.end)}');
    }
    for (var i = startIndex; i <= endIndex; i++) {
      if (i > beforeStart) buffer.write('\n');
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      buffer.write(text.substring(r.start + len, r.end)); // no prefix — turning off
    }
    number = 0; // the "after" segment is a separate list now — starts over
    for (var i = endIndex + 1; i <= afterEnd; i++) {
      buffer.write('\n');
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      buffer.write('$indent$number. ${text.substring(r.start + len, r.end)}');
    }

    return (start: records[beforeStart].start, end: records[afterEnd].end, text: buffer.toString());
  }

  /// Computes the edit to indent (`outdent: false`, adds 2 leading
  /// spaces) or outdent (`outdent: true`, removes up to 2) every
  /// paragraph `selection` spans that has a list prefix. Paragraphs in
  /// range without one are left untouched (their content still gets
  /// carried through the combined replacement unchanged).
  ///
  /// Same shape and safety reasoning as [listToggleEdit]: one atomic
  /// replacement computed entirely from the current document, no
  /// intermediate mutation, so a multi-paragraph selection needs no
  /// composite command — collapses to the single-paragraph case
  /// naturally when `selection` is collapsed.
  ///
  /// Returns `null` if nothing in range would actually change — no
  /// paragraph in the selection has a list prefix, or every one being
  /// outdented is already at the top level.
  ({int start, int end, String text})? listIndentEdit(EditorSelection selection, {required bool outdent}) {
    final text = document.text;
    final records = document.paragraphs.records;
    final startRecord = document.paragraphs.paragraphAt(selection.start);
    if (startRecord == null) return null;
    final endRecord = document.paragraphs.paragraphAt(selection.end) ?? startRecord;
    final startIndex = records.indexOf(startRecord);
    final endIndex = records.indexOf(endRecord);
    if (startIndex == -1 || endIndex == -1) return null;

    final buffer = StringBuffer();
    var anyChange = false;
    for (var i = startIndex; i <= endIndex; i++) {
      if (i > startIndex) buffer.write('\n');
      final r = records[i];
      final prefixLen = listPrefixLength(text, r.start);
      if (prefixLen == 0) {
        buffer.write(text.substring(r.start, r.end));
        continue;
      }

      final prefix = text.substring(r.start, r.start + prefixLen);
      final leadingWs = RegExp(r'^[ \t]*').firstMatch(prefix)!.group(0)!;
      final markerRest = prefix.substring(leadingWs.length); // '- ' / '1. ', indent stripped
      final content = text.substring(r.start + prefixLen, r.end);

      final newIndent = outdent
          ? (leadingWs.length >= 2 ? leadingWs.substring(2) : '')
          : '$leadingWs  ';
      if (newIndent != leadingWs) anyChange = true;
      buffer.write('$newIndent$markerRest$content');
    }

    if (!anyChange) return null;
    return (start: startRecord.start, end: endRecord.end, text: buffer.toString());
  }

  /// Toggles `type` over `selection`.
  ///
  /// - Not collapsed: if a single span already covers the whole
  ///   selection, the attribute is removed; otherwise it's applied to
  ///   the whole selection (this matches "make bold" semantics — a
  ///   partially-bold selection becomes fully bold on first toggle, not
  ///   fully un-bold).
  /// - Collapsed: toggles [stickyAttributes] instead of touching any
  ///   span, so the next typed text picks it up.
  ///
  /// Only valid for [AttributeType.isToggle] types — use [applyAttribute]
  /// for color/size/link, or [setHeaderLevel] for header, which carry a
  /// value.
  /// Clips `selection` so it never *starts* inside a paragraph's list
  /// marker zone — prevents inline formatting (bold, italic, ...) from
  /// splitting a marker from its own trailing space (a bold `'-'` next
  /// to non-bold `' Item'` reads as broken, not as "a formatted list
  /// item"). Purely derived from text (`listPrefixLength`), same as
  /// everywhere else list-ness is checked — nothing stored, nothing
  /// that could drift from what's actually typed.
  ///
  /// Only adjusts the start: a selection ending mid-marker (selecting
  /// backward, from inside the item's own text into the marker) is left
  /// alone — a genuine edge case, not attempted here.
  EditorSelection _excludeLeadingListMarker(EditorSelection selection) {
    final record = document.paragraphs.paragraphAt(selection.start);
    if (record == null) return selection;
    final prefixLen = listPrefixLength(document.text, record.start);
    final markerEnd = record.start + prefixLen;
    if (selection.start >= record.start && selection.start < markerEnd) {
      final newStart = markerEnd > selection.end ? selection.end : markerEnd;
      return EditorSelection(baseOffset: newStart, extentOffset: selection.end);
    }
    return selection;
  }

  void toggleAttribute(AttributeType type, EditorSelection selection) {
    assert(type.isToggle,
    'toggleAttribute is for toggle-style attributes only; use applyAttribute for $type');

    if (selection.isCollapsed) {
      if (_stickyAttributes.containsKey(type)) {
        _stickyAttributes.remove(type);
      } else {
        _stickyAttributes[type] = null;
      }
      transactions.notify();
      return;
    }

    final range = _excludeLeadingListMarker(selection);
    if (range.isCollapsed) {
      transactions.notify();
      return;
    }

    final store = document.attributeStore;
    final alreadyCovered = store.coversRange(range.start, range.end, type);

    store.clearRange(range.start, range.end, type: type);
    if (!alreadyCovered) {
      store.insert(TextAttribute(start: range.start, end: range.end, type: type));
      _stickyAttributes[type] = null;
    } else {
      _stickyAttributes.remove(type);
    }
    store.optimize(type: type);

    transactions.notify();
  }

  /// Sets `type` to `value` over `selection`. Passing `value: null` is
  /// equivalent to calling [removeAttribute].
  ///
  /// Not for [AttributeType.header] — use [setHeaderLevel] instead;
  /// header no longer goes through the generic attribute path at all
  /// (see the block-architecture design notes).
  void applyAttribute(AttributeType type, EditorSelection selection, Object? value) {
    assert(type != AttributeType.header, 'use setHeaderLevel for header, not applyAttribute');

    if (value == null) {
      removeAttribute(type, selection);
      return;
    }

    if (selection.isCollapsed) {
      _stickyAttributes[type] = value;
      transactions.notify();
      return;
    }

    final range = _excludeLeadingListMarker(selection);
    if (range.isCollapsed) {
      transactions.notify();
      return;
    }

    final store = document.attributeStore;
    store.clearRange(range.start, range.end, type: type);

    store.insert(TextAttribute(start: range.start, end: range.end, type: type, value: value));
    store.optimize(type: type);
    _stickyAttributes[type] = value;

    transactions.notify();
  }

  /// Removes `type` from `selection`.
  ///
  /// Not for [AttributeType.header] — use `setHeaderLevel(selection,
  /// null)` instead; see [applyAttribute]'s doc comment.
  void removeAttribute(AttributeType type, EditorSelection selection) {
    assert(type != AttributeType.header, 'use setHeaderLevel(selection, null) for header, not removeAttribute');

    if (selection.isCollapsed) {
      _stickyAttributes.remove(type);
      transactions.notify();
      return;
    }

    document.attributeStore.clearRange(selection.start, selection.end, type: type);
    _stickyAttributes.remove(type);

    transactions.notify();
  }

  /// Removes every attribute from `selection`. At a collapsed caret,
  /// clears pending [stickyAttributes] instead (so "clear formatting"
  /// with nothing selected stops the *next* typed text from inheriting
  /// formatting — a small, deliberate improvement over the old
  /// controller, which no-op'd entirely on a collapsed selection).
  ///
  /// Also clears `headerLevel` on every paragraph `selection` overlaps
  /// (unexpanded — same bounds used for the `AttributeStore` clear right
  /// above, not paragraph-bounds-expanded), and strips any literal list
  /// marker from those paragraphs too — a real text mutation, computed
  /// by [clearFormattingListEdit] and applied via the ordinary
  /// [replaceRange] path. Wrapped in `transactions.run` since this is
  /// now genuinely two kinds of change (attribute/header state, then
  /// possibly a text edit) composed into one logical operation — without
  /// it, `replaceRange`'s own internal `notify()` plus this method's
  /// final one would trigger two rebuilds instead of one.
  ///
  /// Undo is [ClearFormattingCommand]'s responsibility, not this
  /// method's — it snapshots `AttributeStore` spans, `ParagraphIndex`
  /// header levels, *and* (new) whatever text [clearFormattingListEdit]
  /// is about to rewrite, all before calling this.
  void clearFormatting(EditorSelection selection) {
    if (selection.isCollapsed) {
      if (_stickyAttributes.isEmpty) return;
      _stickyAttributes.clear();
      transactions.notify();
      return;
    }

    transactions.run(() {
      document.attributeStore.clearRange(selection.start, selection.end);
      _stickyAttributes.clear();
      document.paragraphs.setHeaderLevel(selection.start, selection.end, null);

      final listEdit = clearFormattingListEdit(selection);
      if (listEdit != null) {
        replaceRange(listEdit.start, listEdit.end, listEdit.text);
      }

      assert(_debugValidateParagraphs());
      transactions.notify();
    });
  }

  /// Computes the edit to strip literal list markers from every
  /// paragraph `selection` overlaps, if any have one — pure computation,
  /// same shape and safety reasoning as [listToggleEdit]. Returns `null`
  /// if `selection` is collapsed or no paragraph in range has a marker
  /// to strip (avoids a needless no-op replacement).
  ///
  /// Directly reuses [_numberedToggleEdit]'s "turning off" branch rather
  /// than duplicating it: that branch already strips whatever prefix
  /// each paragraph has (bullet or numbered, regardless of type — see
  /// its own doc comment) and renumbers any numbered run left
  /// disconnected by the strip. Exactly what clearing formatting across
  /// a list needs, already hand-traced when it was built for
  /// [listToggleEdit]'s "turn off" case.
  ({int start, int end, String text})? clearFormattingListEdit(EditorSelection selection) {
    if (selection.isCollapsed) return null;
    final text = document.text;
    final records = document.paragraphs.records;
    final startRecord = document.paragraphs.paragraphAt(selection.start);
    if (startRecord == null) return null;
    final endRecord = document.paragraphs.paragraphAt(selection.end) ?? startRecord;
    final startIndex = records.indexOf(startRecord);
    final endIndex = records.indexOf(endRecord);
    if (startIndex == -1 || endIndex == -1) return null;

    var anyMarker = false;
    for (var i = startIndex; i <= endIndex; i++) {
      if (listPrefixLength(text, records[i].start) > 0) {
        anyMarker = true;
        break;
      }
    }
    if (!anyMarker) return null;

    return _numberedToggleEdit(text, records, startIndex, endIndex, false);
  }

  // ---------------------------------------------------------------------
  // Exact restoration (undo support)
  // ---------------------------------------------------------------------

  /// Re-inserts `text` at `start` together with the exact `attributes`
  /// it previously carried, bypassing [stickyAttributes] entirely.
  ///
  /// This exists for undo: when a `HistoryManager` command reverses a
  /// delete or replace, it needs to put back precisely what was removed
  /// — which might be several different formats across the range — not
  /// whatever formatting happens to be pending for new typing right now.
  /// [insert]/[replaceRange] are the wrong tool for that; this is the
  /// right one.
  EditorSelection restoreRange(int start, String text, List<TextAttribute> attributes) {
    assert(start >= 0 && start <= document.length, 'restoreRange start out of bounds');
    if (text.isEmpty) return EditorSelection.collapsed(start);

    final store = document.attributeStore;
    store.shiftForInsertion(start, text.length);
    document.buffer.insert(start, text);
    document.paragraphs.applyInsertion(start, text);
    for (final attr in attributes) {
      store.insert(attr);
      // AttributeStore is no longer written to for header anywhere
      // headers are actively set (see setHeaderLevel) — but `attributes`
      // here can still contain a header-typed entry when this
      // restoration is undoing the deletion of *pasted* content
      // (MarkdownImporter/HtmlImporter still emit header this way, and
      // EditingEngine.pasteRich mirrors it into AttributeStore too — see
      // pasteRich's own comment on why). For that case, this branch is
      // what makes undoing the deletion correctly restore the heading.
      //
      // A header set via SetHeaderLevelCommand (the toolbar/programmatic
      // path, as opposed to paste) never gets an AttributeStore entry at
      // all, so this branch alone can't recover it —
      // ReplaceRangeCommand closes that gap separately, with its own
      // ParagraphIndex snapshot restored after this method returns (see
      // its doc comment). This branch and that one are complementary,
      // not overlapping: this one for headers that arrived via paste,
      // that one for headers set directly.
      if (attr.type == AttributeType.header && attr.end > attr.start) {
        document.paragraphs.setHeaderLevel(attr.start, attr.end, attr.value as String?);
      }
    }
    store.optimize();
    if (text.contains('\n')) {
      _confineParagraphScopedAttributes(start, start + text.length);
    }

    assert(_debugValidateParagraphs());
    transactions.notify();
    return EditorSelection.collapsed(start + text.length);
  }

  /// Replaces [stickyAttributes] wholesale — used by undo/redo for
  /// commands (like clear-formatting at a collapsed caret) whose effect
  /// was entirely on pending sticky state rather than any span.
  void restoreStickyAttributes(Map<AttributeType, Object?> attributes) {
    _stickyAttributes
      ..clear()
      ..addAll(attributes);
    transactions.notify();
  }

  // ---------------------------------------------------------------------
  // Paste
  // ---------------------------------------------------------------------

  /// Plain-text paste: replaces `selection` with `text`, formatted with
  /// whatever [stickyAttributes] are currently pending. An alias for
  /// [insert] under a name that reads clearly at call sites.
  EditorSelection paste(EditorSelection selection, String text) => insert(selection, text);

  /// Rich paste: replaces `selection` with `text`, applying
  /// `relativeAttributes` — spans expressed relative to the start of
  /// `text` (i.e. as if `text` started at offset 0) — at their
  /// corresponding position in the document. Used for pasting from the
  /// system clipboard or between notes, where the incoming content
  /// brings its own formatting rather than inheriting the caret's.
  EditorSelection pasteRich(
      EditorSelection selection,
      String text,
      List<TextAttribute> relativeAttributes,
      ) {
    final store = document.attributeStore;
    final buffer = document.buffer;
    final start = selection.start;

    if (!selection.isCollapsed) {
      store.shiftForDeletion(selection.start, selection.end);
      buffer.delete(selection.start, selection.end);
      document.paragraphs.applyDeletion(selection.start, selection.end);
    }

    if (text.isNotEmpty) {
      store.shiftForInsertion(start, text.length);
      buffer.insert(start, text);
      document.paragraphs.applyInsertion(start, text);

      for (final attr in relativeAttributes) {
        store.insert(TextAttribute(
          start: start + attr.start,
          end: start + attr.end,
          type: attr.type,
          value: attr.value,
        ));
        // Same reasoning as restoreRange: MarkdownImporter/HtmlImporter
        // still emit header as a plain TextAttribute, so a pasted
        // heading needs its own explicit ParagraphIndex write here —
        // applyInsertion above only knows about '\n' positions, not
        // formatting. Inserting into `store` above is otherwise dead
        // weight now (nothing reads header from AttributeStore for a
        // freshly-pasted paragraph going forward). A *subsequent*
        // delete-then-undo of this pasted content is covered separately
        // by ReplaceRangeCommand's own ParagraphIndex snapshot, not by
        // this branch — see its doc comment.
        if (attr.type == AttributeType.header && attr.end > attr.start) {
          document.paragraphs.setHeaderLevel(start + attr.start, start + attr.end, attr.value as String?);
        }
      }
      store.optimize();
      if (text.contains('\n')) {
        _confineParagraphScopedAttributes(start, start + text.length);
      }
    }

    assert(_debugValidateParagraphs());
    transactions.notify();
    return EditorSelection.collapsed(start + text.length);
  }
}