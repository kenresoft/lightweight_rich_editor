import '../models/attribute_type.dart';
import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';
import '../models/text_attribute.dart';
import '../utils/list_prefix.dart';
import 'editor_document.dart';
import 'editor_selection.dart';
import 'paragraph_record.dart';
import 'transaction_manager.dart';

/// All editing logic for an [EditorDocument]: insert, delete, replace,
/// toggle/apply/remove formatting, paste and rich paste, clear
/// formatting. Undo-agnostic — recording undo deltas is the Command
/// layer's job.
///
/// Every mutating method calls [TransactionManager.notify] once. Callers
/// composing several calls into one logical operation should wrap them
/// in `transactions.run(() { ... })` so the UI only rebuilds once.
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
  /// given, otherwise the live [stickyAttributes]. Commands always pass
  /// `attributesForInsertion` explicitly, pinning the exact attributes at
  /// the moment of the edit so redo reproduces it exactly even if the
  /// user has toggled other formatting in between.
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

  // Asserts ParagraphIndex remains internally well-formed (contiguous,
  // gap-free, spanning the whole document) after a mutation. Wrapped in
  // assert(...) at every call site so it's compiled out in release builds.
  bool _debugValidateParagraphs() {
    document.paragraphs.debugValidate(document.text.length);
    return true;
  }

  // Confines link/code spans to the paragraph they started in after a
  // newline insertion — a span that would otherwise run through the new
  // paragraph break gets truncated at the break instead of silently
  // spanning two paragraphs. Header confinement is handled separately, by
  // ParagraphIndex.applyInsertion's split logic.
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
  /// (smart list-marker removal, numbered-list renumbering); most
  /// callers dispatch through [deleteBackwardEdit] directly via a Command
  /// instead.
  EditorSelection deleteBackward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteRange(selection);
    final edit = deleteBackwardEdit(selection);
    if (edit == null) return selection;
    replaceRange(edit.start, edit.end, edit.text);
    return EditorSelection.collapsed(edit.start + edit.cursorOffsetFromStart);
  }

  // Extracts inline attributes intersecting [srcStart, srcEnd) in the
  // current, unmutated document, translated to be relative to destOffset
  // (as if the copied text started at position 0). Used by structural
  // edits that reconstruct a range's text verbatim (list toggle, indent,
  // clear-formatting strip, renumbering) so they carry forward existing
  // inline formatting instead of falling back to sticky attributes, which
  // would risk smearing formatting (e.g. a link) across reconstructed text
  // it never applied to.
  List<TextAttribute> _extractRelativeAttributes(int srcStart, int srcEnd, int destOffset) {
    if (srcEnd <= srcStart) return <TextAttribute>[];
    return document.attributeStore.findIntersecting(srcStart, srcEnd).map((attr) {
      final clippedStart = attr.start < srcStart ? srcStart : attr.start;
      final clippedEnd = attr.end > srcEnd ? srcEnd : attr.end;
      return attr.copyWith(
        start: destOffset + (clippedStart - srcStart),
        end: destOffset + (clippedEnd - srcStart),
      );
    }).toList();
  }

  /// Computes the edit for a backspace at a collapsed caret. Two cases:
  /// 1. Right after a paragraph's list prefix: removes the whole prefix
  ///    in one step, and if that paragraph was part of a numbered run,
  ///    renumbers everything after it down by one (see
  ///    [_removeListMarkerEdit]).
  /// 2. Otherwise: plain single-character deletion.
  ///
  /// Returns `null` for a non-collapsed selection (use [deleteRange]) or
  /// a caret already at document start.
  ({int start, int end, String text, int cursorOffsetFromStart, List<TextAttribute> relativeAttributes})?
  deleteBackwardEdit(EditorSelection selection) {
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

    // Deleting selection.start - 1 alone would orphan a high surrogate if
    // that unit is the low half of a surrogate pair (astral characters,
    // most emoji), so back up one more code unit in that case.
    var deleteStart = selection.start - 1;
    if (deleteStart > 0) {
      final unit = text.codeUnitAt(deleteStart);
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        deleteStart -= 1;
      }
    }
    return (start: deleteStart, end: selection.start, text: '', cursorOffsetFromStart: 0, relativeAttributes: const []);
  }

  // Removes a paragraph's list prefix (record/prefixLen already confirmed
  // to match the caret). A bullet, or a numbered item with nothing after
  // it in the run, is a plain prefix deletion. A numbered item with more
  // items following renumbers all of them down by one as a single
  // combined replacement.
  ({int start, int end, String text, int cursorOffsetFromStart, List<TextAttribute> relativeAttributes})
  _removeListMarkerEdit(ParagraphRecord record, int prefixLen) {
    final text = document.text;
    final prefix = text.substring(record.start, record.start + prefixLen);
    final ownContentStart = record.start + prefixLen;
    final ownContent = text.substring(ownContentStart, record.end);
    final plain = (
    start: record.start,
    end: record.start + prefixLen,
    text: '',
    cursorOffsetFromStart: 0,
    relativeAttributes: const <TextAttribute>[],
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

    final relativeAttrs = _extractRelativeAttributes(ownContentStart, record.end, 0);
    final buffer = StringBuffer(ownContent);
    var number = 0;
    for (var i = currentIndex + 1; i <= lastIndex; i++) {
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final contentStart = r.start + len;
      // Only write the separator once the buffer already has content, so
      // an empty ownContent doesn't leave a leading blank line.
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('$indent$number. ');
      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end));
    }

    return (
    start: record.start,
    end: records[lastIndex].end,
    text: buffer.toString(),
    cursorOffsetFromStart: ownContent.length,
    relativeAttributes: relativeAttrs,
    );
  }

  /// Forward delete: deletes `selection`, or the one character after a
  /// collapsed caret.
  EditorSelection deleteForward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteRange(selection);
    final edit = deleteForwardEdit(selection);
    if (edit == null) return selection;
    replaceRange(edit.start, edit.end, edit.text);
    return EditorSelection.collapsed(edit.start);
  }

  /// Computes the edit for a forward-delete at a collapsed `selection`.
  /// Pressing Delete right before a paragraph's list prefix removes the
  /// whole marker in one step, reusing [_removeListMarkerEdit].
  ({int start, int end, String text, List<TextAttribute> relativeAttributes})? deleteForwardEdit(
      EditorSelection selection,
      ) {
    if (!selection.isCollapsed) return null;
    if (selection.start >= document.length) return null;

    final record = document.paragraphs.paragraphAt(selection.start);
    if (record != null) {
      final prefixLen = listPrefixLength(document.text, record.start);
      if (prefixLen > 0 && selection.start == record.start) {
        final markerEdit = _removeListMarkerEdit(record, prefixLen);
        return (
        start: markerEdit.start,
        end: markerEdit.end,
        text: markerEdit.text,
        relativeAttributes: markerEdit.relativeAttributes,
        );
      }
    }

    // Mirror of deleteBackwardEdit's surrogate-pair check: a high
    // surrogate at selection.start needs its paired low surrogate too.
    var deleteEnd = selection.start + 1;
    if (deleteEnd < document.length) {
      final unit = document.text.codeUnitAt(selection.start);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        deleteEnd += 1;
      }
    }
    return (start: selection.start, end: deleteEnd, text: '', relativeAttributes: const []);
  }

  // ---------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------

  /// The range an [applyAttribute]/[removeAttribute] call for `type`
  /// will actually affect. Always just `selection` — no remaining
  /// `AttributeType` is paragraph-scoped.
  EditorSelection effectiveRangeFor(AttributeType type, EditorSelection selection) {
    return selection;
  }

  /// The paragraph(s) `selection` would expand to for header/alignment/
  /// text-direction purposes — a selection spanning multiple paragraphs
  /// affects all of them.
  EditorSelection paragraphBoundsFor(EditorSelection selection) {
    final startRecord = document.paragraphs.paragraphAt(selection.start);
    final endRecord = document.paragraphs.paragraphAt(selection.end);
    final rangeStart = startRecord?.start ?? selection.start;
    final rangeEnd = endRecord?.end ?? selection.end;
    return EditorSelection(baseOffset: rangeStart, extentOffset: rangeEnd);
  }

  /// Sets `headerLevel` on the paragraph(s) containing `selection`,
  /// driven by [SetHeaderLevelCommand].
  void setHeaderLevel(EditorSelection selection, String? headerLevel) {
    final range = paragraphBoundsFor(selection);
    document.paragraphs.setHeaderLevel(range.start, range.end, headerLevel);
    assert(_debugValidateParagraphs());
    transactions.notify();
  }

  /// Sets `alignment` on the paragraph(s) containing `selection`, driven
  /// by [SetAlignmentCommand].
  void setAlignment(EditorSelection selection, ParagraphAlignment? alignment) {
    final range = paragraphBoundsFor(selection);
    document.paragraphs.setAlignment(range.start, range.end, alignment);
    assert(_debugValidateParagraphs());
    transactions.notify();
  }

  /// Sets `textDirection` on the paragraph(s) containing `selection`,
  /// driven by [SetTextDirectionCommand].
  void setTextDirection(EditorSelection selection, ParagraphTextDirection? textDirection) {
    final range = paragraphBoundsFor(selection);
    document.paragraphs.setTextDirection(range.start, range.end, textDirection);
    assert(_debugValidateParagraphs());
    transactions.notify();
  }

  /// Pure query, no mutation. Answers "if a space were inserted right
  /// now at `spaceInsertPos`, would this be a markdown-style header
  /// shortcut (`'# '`/`'## '`/.../`'###### '`)?" — `null` if not.
  /// `'#{1,6}'` collapses to `'h1'`/`'h2'` since this editor only models
  /// two header levels.
  String? autoFormatHeaderLevel(int spaceInsertPos) {
    final record = document.paragraphs.paragraphAt(spaceInsertPos);
    if (record == null) return null;
    final prefix = document.text.substring(record.start, spaceInsertPos);
    if (!RegExp(r'^#{1,6}$').hasMatch(prefix)) return null;
    return prefix.length == 1 ? 'h1' : 'h2';
  }

  /// Computes the replacement for a live Enter keypress at `selection`:
  /// list continuation as literal text.
  ///
  /// If the paragraph containing the caret begins with a literal
  /// list-style prefix (`'- '`, `'* '`, `'+ '`, or `'N. '`), pressing
  /// Enter continues the list onto the new line by repeating the prefix
  /// (numbered prefixes increment). Pressing Enter on a list item that's
  /// empty except for its prefix exits the list instead.
  ///
  /// Not applied when `selection` isn't collapsed — replacing a real
  /// selection with Enter just inserts a plain newline.
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
  /// sequence. Computed as one combined replacement from the current,
  /// unmutated document rather than a multi-step composite.
  ///
  /// Returns the same shape as [enterKeyEdit] plus `cursorOffsetFromStart`
  /// and `relativeAttributes`. Callers must use
  /// `start + cursorOffsetFromStart` for the resulting caret position,
  /// not `start + text.length` — `text` may include rewritten trailing
  /// items, but the caret belongs right after the *new* item's prefix.
  ///
  /// `stickyAttributesForInsertion` is applied only to the genuinely new
  /// marker text; everything else this method reconstructs (a mid-line
  /// split's tail, renumbered items after it) keeps its own original
  /// attributes via [_extractRelativeAttributes] instead — otherwise a
  /// link covering one word could smear across an entire renumbered
  /// paragraph via leftover sticky state.
  ({int start, int end, String text, int cursorOffsetFromStart, List<TextAttribute> relativeAttributes})
  enterKeyEditWithRenumber(
      EditorSelection selection,
      Map<AttributeType, Object?> stickyAttributesForInsertion,
      ) {
    final base = enterKeyEdit(selection);
    List<TextAttribute> stickyAsRelative(int length) => [
      for (final entry in stickyAttributesForInsertion.entries)
        TextAttribute(start: 0, end: length, type: entry.key, value: entry.value),
    ];
    final plain = (
    start: base.start,
    end: base.end,
    text: base.text,
    cursorOffsetFromStart: base.text.length,
    relativeAttributes: stickyAsRelative(base.text.length),
    );

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

    // Text after the caret on the current line becomes the new item's
    // own content, folded into the same combined replacement.
    final tailContent = text.substring(caret, currentRecord.end);

    if (!matchesRun(currentIndex + 1) && tailContent.isEmpty) {
      return plain;
    }

    var lastIndex = currentIndex;
    while (matchesRun(lastIndex + 1)) {
      lastIndex++;
    }

    var number = int.parse(numberedMatch.group(2)!);
    final buffer = StringBuffer('\n$indent$number. ');
    final relativeAttrs = stickyAsRelative(buffer.length); // sticky applies only to the new marker
    final tailDestOffset = buffer.length;
    relativeAttrs.addAll(_extractRelativeAttributes(caret, currentRecord.end, tailDestOffset));
    buffer.write(tailContent);

    for (var i = currentIndex + 1; i <= lastIndex; i++) {
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final contentStart = r.start + len;
      buffer.write('\n$indent$number. ');
      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end));
    }

    return (
    start: caret,
    end: lastIndex > currentIndex ? records[lastIndex].end : currentRecord.end,
    text: buffer.toString(),
    cursorOffsetFromStart: base.text.length,
    relativeAttributes: relativeAttrs,
    );
  }

  /// Toggles a paragraph (or, for a real selection, every paragraph the
  /// selection spans) between having a list prefix of `type` and not —
  /// as one atomic text replacement, computed entirely from the current
  /// document with no intermediate mutation.
  ///
  /// Bullets only ever touch the selected range. Numbered lists can join
  /// a paragraph to, or split it out of, a run of numbered items
  /// *outside* the selection — see [_numberedToggleEdit].
  ///
  /// Whether this turns the list *on* or *off*: off only if *every*
  /// paragraph in range already has this exact type; on if any of them
  /// doesn't. A mixed selection (some list items, some plain paragraphs)
  /// becomes a list entirely.
  ({int start, int end, String text, List<TextAttribute> relativeAttributes})? listToggleEdit(
      EditorSelection selection,
      ParagraphListType type,
      ) {
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
      final relativeAttrs = <TextAttribute>[];
      for (var i = startIndex; i <= endIndex; i++) {
        if (i > startIndex) buffer.write('\n');
        final r = records[i];
        final prefixLen = listPrefixLength(text, r.start);
        final contentStart = r.start + prefixLen;
        // '  ' default indent, not flush-left: a bare '- ' reads as "just
        // a dash", not a list.
        if (turningOn) buffer.write('  - ');
        final destOffset = buffer.length;
        relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
        buffer.write(text.substring(contentStart, r.end));
      }
      return (start: startRecord.start, end: endRecord.end, text: buffer.toString(), relativeAttributes: relativeAttrs);
    }

    return _numberedToggleEdit(text, records, startIndex, endIndex, turningOn);
  }

  // The numbered half of listToggleEdit — has to consider paragraphs
  // outside [startIndex, endIndex] too.
  //
  // Turning on: may resume a numbered run bordering the selection, so the
  // whole contiguous run gets renumbered together, 1..N.
  //
  // Turning off: removing list-ness from the middle of a run splits it
  // into "before"/"after" segments, each renumbered independently from 1.
  ({int start, int end, String text, List<TextAttribute> relativeAttributes}) _numberedToggleEdit(
      String text,
      List<ParagraphRecord> records,
      int startIndex,
      int endIndex,
      bool turningOn,
      ) {
    String indentOf(int i) {
      final r = records[i];
      if (listPrefixLength(text, r.start) == 0) return '  ';
      return listIndentWhitespace(text, r.start);
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
      // paragraph's own, so it resumes the list it's rejoining.
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
      final relativeAttrs = <TextAttribute>[];
      var number = 0;
      for (var i = runStart; i <= runEnd; i++) {
        if (i > runStart) buffer.write('\n');
        number++;
        final r = records[i];
        final len = listPrefixLength(text, r.start);
        final contentStart = r.start + len;
        buffer.write('$indent$number. ');
        final destOffset = buffer.length;
        relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
        buffer.write(text.substring(contentStart, r.end));
      }
      return (start: records[runStart].start, end: records[runEnd].end, text: buffer.toString(), relativeAttributes: relativeAttrs);
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
    final relativeAttrs = <TextAttribute>[];
    var number = 0;
    for (var i = beforeStart; i < startIndex; i++) {
      if (i > beforeStart) buffer.write('\n');
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final contentStart = r.start + len;
      buffer.write('$indent$number. ');
      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end));
    }
    for (var i = startIndex; i <= endIndex; i++) {
      if (i > beforeStart) buffer.write('\n');
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final contentStart = r.start + len;
      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end)); // no prefix — turning off
    }
    number = 0; // "after" segment is now a separate list, starts over
    for (var i = endIndex + 1; i <= afterEnd; i++) {
      buffer.write('\n');
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final contentStart = r.start + len;
      buffer.write('$indent$number. ');
      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end));
    }

    return (start: records[beforeStart].start, end: records[afterEnd].end, text: buffer.toString(), relativeAttributes: relativeAttrs);
  }

  /// Computes the edit to toggle task-list checkbox state on every
  /// paragraph `selection` spans, per paragraph independently:
  /// - plain paragraph -> promoted to a fresh unchecked task item.
  /// - bullet with no checkbox yet -> a `'[ ] '` checkbox is inserted.
  /// - already a checklist item -> the checked state flips.
  /// - numbered item -> passed through unchanged (not task-compatible).
  ///
  /// Returns `null` if nothing in range would change.
  ({int start, int end, String text, List<TextAttribute> relativeAttributes})? toggleCheckedEdit(
      EditorSelection selection,
      ) {
    final text = document.text;
    final records = document.paragraphs.records;
    final startRecord = document.paragraphs.paragraphAt(selection.start);
    if (startRecord == null) return null;
    final endRecord = document.paragraphs.paragraphAt(selection.end) ?? startRecord;
    final startIndex = records.indexOf(startRecord);
    final endIndex = records.indexOf(endRecord);
    if (startIndex == -1 || endIndex == -1) return null;

    final buffer = StringBuffer();
    final relativeAttrs = <TextAttribute>[];
    var changedAny = false;

    for (var i = startIndex; i <= endIndex; i++) {
      if (i > startIndex) buffer.write('\n');
      final r = records[i];
      final prefixLen = listPrefixLength(text, r.start);
      final contentStart = r.start + prefixLen;

      if (prefixLen == 0) {
        buffer.write('  - [ ] ');
        changedAny = true;
      } else {
        final prefix = text.substring(r.start, contentStart);
        if (listTypeOfPrefix(prefix) == ParagraphListType.numbered) {
          buffer.write(prefix);
        } else {
          final checked = checkboxStateOfPrefix(prefix);
          if (checked == null) {
            buffer.write('$prefix[ ] ');
          } else if (checked) {
            buffer.write(prefix.replaceFirst(RegExp(r'\[[xX]\] $'), '[ ] '));
          } else {
            buffer.write(prefix.replaceFirst(RegExp(r'\[ \] $'), '[x] '));
          }
          changedAny = true;
        }
      }

      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end));
    }

    if (!changedAny) return null;
    return (start: startRecord.start, end: endRecord.end, text: buffer.toString(), relativeAttributes: relativeAttrs);
  }

  /// Computes the edit to indent (`outdent: false`, adds 2 leading
  /// spaces) or outdent (`outdent: true`, removes up to 2) every
  /// paragraph `selection` spans that has a list prefix. Paragraphs in
  /// range without one are left untouched.
  ///
  /// Returns `null` if nothing in range would actually change.
  ({int start, int end, String text, List<TextAttribute> relativeAttributes})? listIndentEdit(
      EditorSelection selection, {
        required bool outdent,
      }) {
    final text = document.text;
    final records = document.paragraphs.records;
    final startRecord = document.paragraphs.paragraphAt(selection.start);
    if (startRecord == null) return null;
    final endRecord = document.paragraphs.paragraphAt(selection.end) ?? startRecord;
    final startIndex = records.indexOf(startRecord);
    final endIndex = records.indexOf(endRecord);
    if (startIndex == -1 || endIndex == -1) return null;

    final buffer = StringBuffer();
    final relativeAttrs = <TextAttribute>[];
    var anyChange = false;
    for (var i = startIndex; i <= endIndex; i++) {
      if (i > startIndex) buffer.write('\n');
      final r = records[i];
      final prefixLen = listPrefixLength(text, r.start);
      if (prefixLen == 0) {
        final destOffset = buffer.length;
        relativeAttrs.addAll(_extractRelativeAttributes(r.start, r.end, destOffset));
        buffer.write(text.substring(r.start, r.end));
        continue;
      }

      final prefix = text.substring(r.start, r.start + prefixLen);
      final leadingWs = RegExp(r'^[ \t]*').firstMatch(prefix)!.group(0)!;
      final markerRest = prefix.substring(leadingWs.length); // '- ' / '1. ', indent stripped
      final contentStart = r.start + prefixLen;

      final newIndent = outdent
          ? (leadingWs.length >= 2 ? leadingWs.substring(2) : '')
          : '$leadingWs  ';
      if (newIndent != leadingWs) anyChange = true;
      buffer.write('$newIndent$markerRest');
      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end));
    }

    if (!anyChange) return null;
    return (start: startRecord.start, end: endRecord.end, text: buffer.toString(), relativeAttributes: relativeAttrs);
  }

  // Clips selection so it never *starts* inside a paragraph's list marker
  // zone — prevents inline formatting from splitting a marker from its
  // own trailing space. Only adjusts the start; a selection ending
  // mid-marker is left alone.
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

  /// Toggles `type` over `selection`.
  ///
  /// - Not collapsed: if a single span already covers the whole
  ///   selection, the attribute is removed; otherwise it's applied to
  ///   the whole selection (a partially-bold selection becomes fully
  ///   bold on first toggle, not fully un-bold).
  /// - Collapsed: toggles [stickyAttributes] instead, so the next typed
  ///   text picks it up.
  ///
  /// Only valid for [AttributeType.isToggle] types — use [applyAttribute]
  /// for color/size/link, or [setHeaderLevel] for header.
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
    }
    store.optimize(type: type);

    transactions.notify();
  }

  /// Sets `type` to `value` over `selection`. Passing `value: null` is
  /// equivalent to calling [removeAttribute].
  ///
  /// Not for [AttributeType.header] — use [setHeaderLevel] instead.
  ///
  /// Deliberately does **not** touch [stickyAttributes] for a
  /// non-collapsed `selection`: sticky state left over from a range apply
  /// would otherwise outlive the edit and silently attach to unrelated
  /// text on a later non-collapsed selection (e.g. "select all" then
  /// paste inheriting a stale link URL). [toggleAttribute] has the same
  /// guard.
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
  /// clears pending [stickyAttributes] instead, so the next typed text
  /// stops inheriting formatting.
  ///
  /// Also clears header/alignment/text-direction on every paragraph
  /// `selection` overlaps, and strips any literal list marker from those
  /// paragraphs via [clearFormattingListEdit]. Wrapped in
  /// `transactions.run` so the combined attribute + text change notifies
  /// once.
  ///
  /// Undo is [ClearFormattingCommand]'s responsibility, not this
  /// method's.
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
      document.paragraphs.setAlignment(selection.start, selection.end, null);
      document.paragraphs.setTextDirection(selection.start, selection.end, null);

      final listEdit = clearFormattingListEdit(selection);
      if (listEdit != null) {
        // pasteRich, not replaceRange: listEdit.relativeAttributes must
        // carry forward the reconstructed paragraphs' existing inline
        // formatting, which replaceRange (falls back to sticky
        // attributes) can't express.
        pasteRich(
          EditorSelection(baseOffset: listEdit.start, extentOffset: listEdit.end),
          listEdit.text,
          listEdit.relativeAttributes,
        );
      }

      assert(_debugValidateParagraphs());
      transactions.notify();
    });
  }

  /// Rewrites every marker in the entire contiguous numbered list
  /// touching `selection` to be sequential (1, 2, 3, ...), regardless of
  /// what the existing numbers currently say. Useful after a range
  /// deletion spanning list items, or content arriving from paste/import.
  ///
  /// Checks the paragraph at `selection.start` first; if that one isn't
  /// itself numbered, falls back to checking the *next* paragraph —
  /// a deletion can consume a paragraph's own marker while leaving an
  /// orphaned numbered run immediately after it.
  ///
  /// Returns `null` if neither the selection's own paragraph nor the
  /// next one is part of a numbered list, or if the run's numbers are
  /// already correct.
  ({int start, int end, String text, List<TextAttribute> relativeAttributes})? repairListNumbering(
      EditorSelection selection,
      ) {
    final text = document.text;
    final records = document.paragraphs.records;
    var record = document.paragraphs.paragraphAt(selection.start);
    if (record == null) return null;

    bool isNumberedRecord(ParagraphRecord r) {
      final len = listPrefixLength(text, r.start);
      if (len == 0) return false;
      return listTypeOfPrefix(text.substring(r.start, r.start + len)) == ParagraphListType.numbered;
    }

    if (!isNumberedRecord(record)) {
      final currentIdx = records.indexOf(record);
      if (currentIdx == -1 || currentIdx + 1 >= records.length) return null;
      final next = records[currentIdx + 1];
      if (!isNumberedRecord(next)) return null;
      record = next;
    }

    final prefixLen = listPrefixLength(text, record.start);
    final prefix = text.substring(record.start, record.start + prefixLen);
    final indent = RegExp(r'^[ \t]*').firstMatch(prefix)!.group(0)!;
    final currentIndex = records.indexOf(record);
    if (currentIndex == -1) return null;

    bool matchesRun(int i) {
      if (i < 0 || i >= records.length) return false;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      if (len == 0) return false;
      final p = text.substring(r.start, r.start + len);
      return listTypeOfPrefix(p) == ParagraphListType.numbered &&
          RegExp(r'^[ \t]*').firstMatch(p)!.group(0)! == indent;
    }

    var runStart = currentIndex;
    while (runStart > 0 && matchesRun(runStart - 1)) {
      runStart--;
    }
    var runEnd = currentIndex;
    while (runEnd < records.length - 1 && matchesRun(runEnd + 1)) {
      runEnd++;
    }

    // If every number in the run already matches its position, there's
    // nothing to rewrite.
    var alreadyCorrect = true;
    var expected = 0;
    for (var i = runStart; i <= runEnd; i++) {
      expected++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final numMatch = RegExp(r'^\d+').firstMatch(text.substring(r.start + indent.length, r.start + len));
      final current = numMatch != null ? int.tryParse(numMatch.group(0)!) : null;
      if (current != expected) {
        alreadyCorrect = false;
        break;
      }
    }
    if (alreadyCorrect) return null;

    final buffer = StringBuffer();
    final relativeAttrs = <TextAttribute>[];
    var number = 0;
    for (var i = runStart; i <= runEnd; i++) {
      if (i > runStart) buffer.write('\n');
      number++;
      final r = records[i];
      final len = listPrefixLength(text, r.start);
      final contentStart = r.start + len;
      buffer.write('$indent$number. ');
      final destOffset = buffer.length;
      relativeAttrs.addAll(_extractRelativeAttributes(contentStart, r.end, destOffset));
      buffer.write(text.substring(contentStart, r.end));
    }

    return (
    start: records[runStart].start,
    end: records[runEnd].end,
    text: buffer.toString(),
    relativeAttributes: relativeAttrs,
    );
  }

  /// Computes the edit to strip literal list markers from every
  /// paragraph `selection` overlaps, if any have one. Returns `null` if
  /// `selection` is collapsed or no paragraph in range has a marker to
  /// strip. Reuses [_numberedToggleEdit]'s "turning off" branch, which
  /// already renumbers any disconnected numbered run and preserves
  /// inline attributes.
  ({int start, int end, String text, List<TextAttribute> relativeAttributes})? clearFormattingListEdit(
      EditorSelection selection,
      ) {
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
  /// Exists for undo: reversing a delete/replace needs to put back
  /// precisely what was removed, not whatever sticky formatting happens
  /// to be pending right now.
  EditorSelection restoreRange(int start, String text, List<TextAttribute> attributes) {
    assert(start >= 0 && start <= document.length, 'restoreRange start out of bounds');
    if (text.isEmpty) return EditorSelection.collapsed(start);

    final store = document.attributeStore;
    store.shiftForInsertion(start, text.length);
    document.buffer.insert(start, text);
    document.paragraphs.applyInsertion(start, text);
    for (final attr in attributes) {
      store.insert(attr);
      // header/align/textDirection are ParagraphIndex-owned everywhere
      // they're live, so an entry of these types in `attributes` can only
      // have arrived via pasted content — mirror it into ParagraphIndex
      // too. A header/alignment/direction set directly (not via paste)
      // never gets an AttributeStore entry, so ReplaceRangeCommand
      // restores that case separately via its own ParagraphIndex
      // snapshot.
      if (attr.type == AttributeType.header && attr.end > attr.start) {
        document.paragraphs.setHeaderLevel(attr.start, attr.end, attr.value as String?);
      }
      if (attr.type == AttributeType.align && attr.end > attr.start) {
        document.paragraphs.setAlignment(
          attr.start,
          attr.end,
          attr.value == null ? null : ParagraphAlignment.values.byName(attr.value as String),
        );
      }
      if (attr.type == AttributeType.textDirection && attr.end > attr.start) {
        document.paragraphs.setTextDirection(
          attr.start,
          attr.end,
          attr.value == null ? null : ParagraphTextDirection.values.byName(attr.value as String),
        );
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
        // Pasted content (Markdown/HTML import) still carries
        // header/align/textDirection as plain TextAttributes, so mirror
        // them into ParagraphIndex explicitly here — applyInsertion only
        // knows about '\n' positions, not formatting.
        if (attr.type == AttributeType.header && attr.end > attr.start) {
          document.paragraphs.setHeaderLevel(start + attr.start, start + attr.end, attr.value as String?);
        }
        if (attr.type == AttributeType.align && attr.end > attr.start) {
          document.paragraphs.setAlignment(
            start + attr.start,
            start + attr.end,
            attr.value == null ? null : ParagraphAlignment.values.byName(attr.value as String),
          );
        }
        if (attr.type == AttributeType.textDirection && attr.end > attr.start) {
          document.paragraphs.setTextDirection(
            start + attr.start,
            start + attr.end,
            attr.value == null ? null : ParagraphTextDirection.values.byName(attr.value as String),
          );
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