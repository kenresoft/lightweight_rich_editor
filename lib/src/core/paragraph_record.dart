import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';

/// One paragraph's boundaries and block-level metadata.
class ParagraphRecord {
  /// Inclusive offset of this paragraph's first character.
  final int start;

  /// The position of this paragraph's own trailing `'\n'`, exclusive of
  /// its own content — i.e. `text.substring(start, end)` is this
  /// paragraph's text without the newline. Equals `text.length` for the
  /// last paragraph in the document.
  final int end;

  /// `'h1'` | `'h2'` | `null`.
  final String? headerLevel;

  /// `null` (default/left) | `center` | `right`. Stored and
  /// round-tripped, but not yet rendered with a live visual effect.
  final ParagraphAlignment? alignment;

  /// `null` (unspecified — ambient `Directionality`) | `ltr` | `rtl`.
  /// Same no-live-rendering-effect caveat as [alignment].
  final ParagraphTextDirection? textDirection;

  const ParagraphRecord({
    required this.start,
    required this.end,
    this.headerLevel,
    this.alignment,
    this.textDirection,
  });

  /// Whether `offset` belongs to this paragraph. Inclusive on both ends.
  bool contains(int offset) => offset >= start && offset <= end;

  ParagraphRecord copyWith({
    int? start,
    int? end,
    String? headerLevel,
    bool clearHeaderLevel = false,
    ParagraphAlignment? alignment,
    bool clearAlignment = false,
    ParagraphTextDirection? textDirection,
    bool clearTextDirection = false,
  }) {
    return ParagraphRecord(
      start: start ?? this.start,
      end: end ?? this.end,
      headerLevel: clearHeaderLevel ? null : (headerLevel ?? this.headerLevel),
      alignment: clearAlignment ? null : (alignment ?? this.alignment),
      textDirection: clearTextDirection ? null : (textDirection ?? this.textDirection),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ParagraphRecord &&
          other.start == start &&
          other.end == end &&
          other.headerLevel == headerLevel &&
          other.alignment == alignment &&
          other.textDirection == textDirection;

  @override
  int get hashCode => Object.hash(start, end, headerLevel, alignment, textDirection);

  @override
  String toString() =>
      'ParagraphRecord($start, $end, headerLevel: $headerLevel, alignment: $alignment, textDirection: $textDirection)';
}
