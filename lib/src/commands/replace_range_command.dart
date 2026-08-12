import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Replaces `[start, end)` (positions in the document as it stood
/// *before* this command runs) with `text`. Covers insert (`start ==
/// end`), delete (`text.isEmpty`), plain replace, plain-text paste, and
/// rich paste (via `relativeAttributes`) — every text-content edit is
/// one of these, mirroring how [EditingEngine.replaceRange] is the one
/// primitive underneath all of them.
///
/// Exactly one of `attributesForInsertion` / `relativeAttributes` is
/// meaningful for a given command:
/// - `attributesForInsertion`: a flat set applied to the whole inserted
///   run — typing with sticky formatting on, or a plain-text paste.
/// - `relativeAttributes`: per-character spans expressed relative to the
///   start of `text` — a rich paste bringing its own formatting.
///
/// Undo is exact, not best-effort: [execute] snapshots the text and
/// spans it's about to remove *every time it runs* (so redo — which
/// calls [execute] again — snapshots correctly too), and [undo] restores
/// that exact snapshot via [EditingEngine.restoreRange] rather than
/// re-deriving it from sticky attributes or guessing.
///
/// [_removedHeaderLevels] is a second, separate snapshot alongside
/// [_removedSpans] — header lives in `ParagraphIndex` now, not
/// `AttributeStore` (see the block-architecture design notes), so a
/// deleted paragraph's `headerLevel` isn't recoverable from
/// `_removedSpans` the way it used to be. Concretely: deleting a
/// paragraph headed via `SetHeaderLevelCommand` (as opposed to an old
/// paragraph loaded from a note saved before that migration) leaves
/// nothing in `AttributeStore` to snapshot at all — `_removedSpans`
/// would simply be missing the header entry, and undo would silently
/// restore the text without the heading. This snapshot is what closes
/// that gap. It's redundant (harmless, not wrong) for a pure insert —
/// `ParagraphIndex.applyDeletion`'s "keep the leftmost fragment's
/// headerLevel on merge" rule is the exact inverse of
/// `applyInsertion`'s "keep the first fragment's headerLevel on split",
/// so undoing a pure insert via a symmetric deletion already restores
/// the original headerLevel on its own; the snapshot only does real
/// work for delete/replace.
class ReplaceRangeCommand extends EditorCommand {
  final int start;
  final int end;
  final String text;
  final Map<AttributeType, Object?>? attributesForInsertion;
  final List<TextAttribute>? relativeAttributes;

  String? _removedText;
  List<TextAttribute>? _removedSpans;
  List<({int start, int end, String? headerLevel})>? _removedHeaderLevels;

  ReplaceRangeCommand({
    required this.start,
    required this.end,
    required this.text,
    this.attributesForInsertion,
    this.relativeAttributes,
  }) : assert(end >= start, 'end must not be before start'),
        assert(
        attributesForInsertion == null || relativeAttributes == null,
        'pass at most one of attributesForInsertion / relativeAttributes',
        );

  bool get _isPureInsert => start == end && text.isNotEmpty;

  bool get _isPureDelete => text.isEmpty && end > start;

  @override
  EditorSelection execute(EditingEngine engine) {
    final store = engine.document.attributeStore;
    final length = engine.document.buffer.length;
    final safeStart = start.clamp(0, length);
    final safeEnd = end.clamp(safeStart, length);

    _removedText = engine.document.buffer.substring(safeStart, safeEnd);
    _removedSpans = store.findIntersecting(safeStart, safeEnd);
    _removedHeaderLevels = engine.document.paragraphs
        .recordsOverlapping(safeStart, safeEnd)
        .map((r) => (start: r.start, end: r.end, headerLevel: r.headerLevel))
        .toList(growable: false);

    if (relativeAttributes != null) {
      return engine.pasteRich(
        EditorSelection(baseOffset: safeStart, extentOffset: safeEnd),
        text,
        relativeAttributes!,
      );
    }
    return engine.replaceRange(safeStart, safeEnd, text, attributesForInsertion: attributesForInsertion);
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      final insertedEnd = start + text.length;
      if (insertedEnd > start) {
        engine.replaceRange(start, insertedEnd, '');
      }
      final result = engine.restoreRange(start, _removedText ?? '', _removedSpans ?? const []);
      for (final snapshot in _removedHeaderLevels ?? const []) {
        engine.document.paragraphs.setHeaderLevel(snapshot.start, snapshot.end, snapshot.headerLevel);
      }
      engine.transactions.notify();
      return result;
    });
  }

  @override
  bool canCoalesceWith(EditorCommand previous) {
    if (previous is! ReplaceRangeCommand) return false;

    // Rich-paste and attributed inserts never coalesce with anything —
    // they represent a single deliberate action, not incremental typing.
    if (relativeAttributes != null || previous.relativeAttributes != null) return false;

    if (_isPureInsert && previous._isPureInsert) {
      return start == previous.start + previous.text.length &&
          _sameAttributeIntent(attributesForInsertion, previous.attributesForInsertion);
    }

    if (_isPureDelete && previous._isPureDelete) {
      final backspaceChain = end == previous.start; // deleting leftward
      final forwardDeleteChain = start == previous.start; // deleting rightward
      return backspaceChain || forwardDeleteChain;
    }

    return false;
  }

  bool _sameAttributeIntent(
      Map<AttributeType, Object?>? a,
      Map<AttributeType, Object?>? b,
      ) {
    final left = a ?? const {};
    final right = b ?? const {};
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) return false;
    }
    return true;
  }
}