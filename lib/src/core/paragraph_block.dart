import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';
import '../utils/list_prefix.dart';
import 'paragraph_record.dart';

/// A paragraph's [ParagraphRecord] plus every block-level property
/// derivable from it and the document's text, resolved once into one
/// clean, read-only object.
///
/// [listType], [checked], and [indentLevel] are computed fresh from
/// `text` every time [ParagraphBlock.derive] runs rather than cached on
/// [ParagraphRecord], so nothing here can go stale.
class ParagraphBlock {
  final ParagraphRecord record;
  final ParagraphListType? listType;

  /// `null` if this paragraph isn't a task-list item (including every
  /// numbered item); `true`/`false` for checked/unchecked.
  final bool? checked;

  /// Nesting depth in indent levels (2 leading spaces per level).
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
