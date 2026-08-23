import '../core/editing_engine.dart';
import '../core/editor_selection.dart';
import '../core/paragraph_record.dart';
import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import 'editor_command.dart';

/// Replaces `[start, end)` (positions in the document as it stood
/// *before* this command runs) with `text`. Covers insert (`start ==
/// end`), delete (`text.isEmpty`), plain replace, plain-text paste, and
/// rich paste (via `relativeAttributes`) — every text-content edit goes
/// through this command.
///
/// Exactly one of `attributesForInsertion` / `relativeAttributes` is
/// meaningful for a given command:
/// - `attributesForInsertion`: a flat set applied to the whole inserted
///   run — typing with sticky formatting on, or a plain-text paste.
/// - `relativeAttributes`: per-character spans expressed relative to the
///   start of `text` — a rich paste bringing its own formatting.
///
/// [execute] snapshots the text, spans, and paragraph block metadata
/// (`headerLevel`/`alignment` live in `ParagraphIndex`, not
/// `AttributeStore`, so they need their own snapshot) it's about to
/// remove every time it runs, so [undo] can restore the exact prior
/// state via [EditingEngine.restoreRange].
class ReplaceRangeCommand extends EditorCommand {
  final int start;
  final int end;
  final String text;
  final Map<AttributeType, Object?>? attributesForInsertion;
  final List<TextAttribute>? relativeAttributes;

  String? _removedText;
  List<TextAttribute>? _removedSpans;
  List<ParagraphRecord>? _removedBlockMetadata;

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
    _removedBlockMetadata = engine.document.paragraphs.recordsOverlapping(safeStart, safeEnd);

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
      engine.document.paragraphs.restoreBlockMetadata(_removedBlockMetadata ?? const []);
      engine.transactions.notify();
      return result;
    });
  }

  @override
  bool canCoalesceWith(EditorCommand previous) {
    if (previous is! ReplaceRangeCommand) return false;

    // Rich-paste never coalesces — it's a single deliberate action.
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