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
class ReplaceRangeCommand extends EditorCommand {
  final int start;
  final int end;
  final String text;
  final Map<AttributeType, Object?>? attributesForInsertion;
  final List<TextAttribute>? relativeAttributes;

  String? _removedText;
  List<TextAttribute>? _removedSpans;

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
    _removedText = engine.document.buffer.substring(start, end);
    _removedSpans = store.findIntersecting(start, end);

    if (relativeAttributes != null) {
      return engine.pasteRich(
        EditorSelection(baseOffset: start, extentOffset: end),
        text,
        relativeAttributes!,
      );
    }
    return engine.replaceRange(start, end, text, attributesForInsertion: attributesForInsertion);
  }

  @override
  EditorSelection undo(EditingEngine engine) {
    return engine.transactions.run(() {
      final insertedEnd = start + text.length;
      if (insertedEnd > start) {
        engine.replaceRange(start, insertedEnd, '');
      }
      return engine.restoreRange(start, _removedText ?? '', _removedSpans ?? const []);
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