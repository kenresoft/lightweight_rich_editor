import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';
import '../utils/list_prefix.dart';
import 'paragraph_record.dart';

/// A paragraph's [ParagraphRecord] plus every block-level property
/// derivable from it and the document's text, resolved once into one
/// clean, read-only object.
///
/// This does *not* introduce a new source of truth: [listType]/[checked]/
/// [indentLevel] are computed fresh from `text` every time
/// [ParagraphBlock.derive] runs (same rule [listPrefixLength]/
/// [listTypeOfPrefix] already follow — see their own doc comments), never
/// cached on [ParagraphRecord] itself. `ParagraphIndex` deliberately has
/// no access to document text (see its `_containsListPrefix`-adjacent
/// reasoning in `TextSpanRenderer`), so nothing here could go stale the
/// way a stored-but-derivable field could.
///
/// What this *does* replace is callers hand-rolling their own
/// `listPrefixLength`/regex calls to answer "what kind of block is this
/// paragraph" — `EditingEngine`, `TextSpanRenderer`, `CommandDispatcher`,
/// and the exporters each used to do this independently, which is exactly
/// how a single indentation-parsing bug (`EditingEngine`'s former private
/// `indentOf`) shipped without the other call sites noticing anything was
/// wrong. One derivation, one place, reused everywhere a caller needs the
/// full picture rather than just one property.
class ParagraphBlock {
  final ParagraphRecord record;
  final ParagraphListType? listType;

  /// `null` if this paragraph isn't a task-list item at all (including
  /// every numbered item — see [checkboxStateOfPrefix]); `true`/`false`
  /// for a checked/unchecked one.
  final bool? checked;

  /// Nesting depth in indent levels (2 leading spaces per level) —
  /// derived from [listIndentWhitespace], independent of whether this
  /// paragraph has a list prefix at all.
  final int indentLevel;

  const ParagraphBlock({
    required this.record,
    required this.listType,
    required this.checked,
    required this.indentLevel,
  });

  int get start => record.start;
  int get end => record.end;
  String? get headerLevel => record.headerLevel;
  ParagraphAlignment? get alignment => record.alignment;
  ParagraphTextDirection? get textDirection => record.textDirection;

  factory ParagraphBlock.derive(ParagraphRecord record, String text) {
    final prefixLen = listPrefixLength(text, record.start);
    ParagraphListType? listType;
    bool? checked;
    if (prefixLen > 0) {
      final prefix = text.substring(record.start, record.start + prefixLen);
      listType = listTypeOfPrefix(prefix);
      checked = checkboxStateOfPrefix(prefix);
    }
    final indentLevel = listIndentWhitespace(text, record.start).length ~/ 2;
    return ParagraphBlock(
      record: record,
      listType: listType,
      checked: checked,
      indentLevel: indentLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ParagraphBlock &&
          other.record == record &&
          other.listType == listType &&
          other.checked == checked &&
          other.indentLevel == indentLevel;

  @override
  int get hashCode => Object.hash(record, listType, checked, indentLevel);

  @override
  String toString() =>
      'ParagraphBlock($record, listType: $listType, checked: $checked, indentLevel: $indentLevel)';
}
