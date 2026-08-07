import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_document.dart';
import 'editor_selection.dart';
import 'transaction_manager.dart';

/// All editing logic for an [EditorDocument]: insert, delete, replace,
/// toggle/apply/remove formatting, paste and rich paste, clear
/// formatting — every operation the old `RichTextEditingController` did
/// by hand-rolling text and span math inline.
///
/// [EditingEngine] talks to the document only through [EditorDocument]'s
/// [TextBuffer] and [AttributeStore] — it never touches a raw `String`.
/// It's also undo-agnostic on purpose: it doesn't know a `HistoryManager`
/// exists. Recording undo deltas is a wrapping concern that belongs to
/// the Command layer (Phase 3), not something every editing method here
/// should have to remember to do.
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
    }

    if (text.isNotEmpty) {
      store.shiftForInsertion(start, text.length);
      buffer.insert(start, text);

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

    transactions.notify();
    return EditorSelection.collapsed(start + text.length);
  }

  /// Trims any [AttributeType.isParagraphScoped] span (currently just
  /// [AttributeType.header]) that now crosses a newline within
  /// `[rangeStart, rangeEnd)`, cutting it off *before* the newline.
  ///
  /// Without this, [AttributeStore.shiftForInsertion]'s span-absorbs-the-
  /// insertion-point rule — correct for character-level formatting, so
  /// typing in the middle of bold text stays bold — also lets a header
  /// span silently absorb a newline typed at its end. Every character
  /// typed immediately after then lands exactly at the span's new end,
  /// growing it again, one character at a time: the header visibly
  /// bleeds onto the next paragraph as the user types. A header is a
  /// property of exactly one paragraph, so this confines it after any
  /// insertion that could have introduced one. The paragraph *after* the
  /// newline is left with no header at all — matching the standard
  /// "pressing Enter after a heading returns to body text" behavior in
  /// Notion, Google Docs, and Word.
  void _confineParagraphScopedAttributes(int rangeStart, int rangeEnd) {
    final text = document.text;
    final store = document.attributeStore;
    final end = rangeEnd < text.length ? rangeEnd : text.length;

    for (var i = rangeStart; i < end; i++) {
      if (text.codeUnitAt(i) != 0x0A) continue;

      for (final type in AttributeType.values) {
        if (!type.isParagraphScoped) continue;
        for (final span in store.findIntersecting(i, i + 1, type: type)) {
          store.remove(span);
          if (span.start < i) {
            store.insert(span.copyWith(end: i));
          }
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
  /// collapsed caret.
  ///
  /// Note: this deletes one UTF-16 code unit, same granularity as the
  /// original controller. It does not currently combine surrogate pairs
  /// or grapheme clusters (emoji, combining marks) into a single delete
  /// — worth revisiting with the `characters` package if that surfaces
  /// as a real bug, but it wasn't handled before either, so this isn't a
  /// regression.
  EditorSelection deleteBackward(EditorSelection selection) {
    if (!selection.isCollapsed) return deleteRange(selection);
    if (selection.start == 0) return selection;
    return replaceRange(selection.start - 1, selection.start, '');
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

  /// The range an [applyAttribute]/[removeAttribute] call for `type` will
  /// actually affect: `selection` itself, or its enclosing paragraph for
  /// [AttributeType.isParagraphScoped] types (currently just
  /// [AttributeType.header]). Exposed publicly so command/undo code can
  /// snapshot precisely the spans about to change, without duplicating
  /// paragraph-bounds logic.
  EditorSelection effectiveRangeFor(AttributeType type, EditorSelection selection) {
    return type.isParagraphScoped ? _paragraphBounds(selection) : selection;
  }

  EditorSelection _paragraphBounds(EditorSelection selection) {
    final text = document.text;
    if (text.isEmpty) return const EditorSelection.collapsed(0);

    int pStart =
    selection.start <= 0 ? -1 : text.lastIndexOf('\n', selection.start - 1);
    pStart = pStart == -1 ? 0 : pStart + 1;

    int pEnd = text.indexOf('\n', selection.end);
    pEnd = pEnd == -1 ? text.length : pEnd;

    return EditorSelection(baseOffset: pStart, extentOffset: pEnd);
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
  /// for color/size/link/header, which carry a value.
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

    final store = document.attributeStore;
    final alreadyCovered = store.coversRange(selection.start, selection.end, type);

    store.clearRange(selection.start, selection.end, type: type);
    if (!alreadyCovered) {
      store.insert(TextAttribute(start: selection.start, end: selection.end, type: type));
      _stickyAttributes[type] = null;
    } else {
      _stickyAttributes.remove(type);
    }
    store.optimize(type: type);

    transactions.notify();
  }

  /// Sets `type` to `value` over `selection` (or, for
  /// [AttributeType.isParagraphScoped] types like [AttributeType.header],
  /// over the whole paragraph containing `selection`). Passing
  /// `value: null` is equivalent to calling [removeAttribute].
  void applyAttribute(AttributeType type, EditorSelection selection, Object? value) {
    if (value == null) {
      removeAttribute(type, selection);
      return;
    }

    final range = type.isParagraphScoped ? _paragraphBounds(selection) : selection;

    if (range.isCollapsed && !type.isParagraphScoped) {
      _stickyAttributes[type] = value;
      transactions.notify();
      return;
    }

    final store = document.attributeStore;
    store.clearRange(range.start, range.end, type: type);
    store.insert(TextAttribute(start: range.start, end: range.end, type: type, value: value));
    store.optimize(type: type);
    if (!type.isParagraphScoped) _stickyAttributes[type] = value;

    transactions.notify();
  }

  /// Removes `type` from `selection` (or the enclosing paragraph, for
  /// paragraph-scoped types).
  void removeAttribute(AttributeType type, EditorSelection selection) {
    final range = type.isParagraphScoped ? _paragraphBounds(selection) : selection;

    if (range.isCollapsed) {
      _stickyAttributes.remove(type);
      transactions.notify();
      return;
    }

    document.attributeStore.clearRange(range.start, range.end, type: type);
    _stickyAttributes.remove(type);
    transactions.notify();
  }

  /// Removes every attribute from `selection`. At a collapsed caret,
  /// clears pending [stickyAttributes] instead (so "clear formatting"
  /// with nothing selected stops the *next* typed text from inheriting
  /// formatting — a small, deliberate improvement over the old
  /// controller, which no-op'd entirely on a collapsed selection).
  void clearFormatting(EditorSelection selection) {
    if (selection.isCollapsed) {
      if (_stickyAttributes.isEmpty) return;
      _stickyAttributes.clear();
      transactions.notify();
      return;
    }

    document.attributeStore.clearRange(selection.start, selection.end);
    _stickyAttributes.clear();
    transactions.notify();
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
    for (final attr in attributes) {
      store.insert(attr);
    }
    store.optimize();
    if (text.contains('\n')) {
      _confineParagraphScopedAttributes(start, start + text.length);
    }

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
    }

    if (text.isNotEmpty) {
      store.shiftForInsertion(start, text.length);
      buffer.insert(start, text);

      for (final attr in relativeAttributes) {
        store.insert(TextAttribute(
          start: start + attr.start,
          end: start + attr.end,
          type: attr.type,
          value: attr.value,
        ));
      }
      store.optimize();
      if (text.contains('\n')) {
        _confineParagraphScopedAttributes(start, start + text.length);
      }
    }

    transactions.notify();
    return EditorSelection.collapsed(start + text.length);
  }
}