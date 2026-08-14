import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';

/// One paragraph's boundaries and block-level metadata.
///
/// [headerLevel], [alignment], and [textDirection] are the only populated
/// fields. This is not a catch-all block model: new fields (list type,
/// indent level, checked state — deliberately *not* added here; see
/// `EditingEngine.listToggleEdit`'s doc comment on why those stay literal
/// text, derived on demand via `ParagraphBlock` rather than stored) get
/// added only when a concrete, approved feature needs them and has no
/// possible textual representation, following the same "small and
/// intentionally closed" discipline `AttributeType` already follows.
class ParagraphRecord {
  /// Inclusive offset of this paragraph's first character.
  final int start;

  /// The position of this paragraph's own trailing `'\n'` — exclusive of
  /// its own content, i.e. `text.substring(start, end)` is this
  /// paragraph's text without the newline. For the last paragraph in the
  /// document (which has no trailing newline), this equals
  /// `text.length`.
  final int end;

  /// `'h1'` | `'h2'` | `null`. Mirrors `AttributeType.header`'s value
  /// space exactly, by design — this is a parallel, dual-written
  /// representation during migration (see `EditingEngine`'s dual-write
  /// call sites), not a new value space of its own.
  final String? headerLevel;

  /// `null` (the default/left) | `center` | `right`. See
  /// [ParagraphAlignment]'s own doc comment for the important caveat:
  /// stored and round-tripped, but not yet rendered with any live visual
  /// effect — the single `TextField` this package renders through can't
  /// vary `textAlign` per paragraph.
  final ParagraphAlignment? alignment;

  /// `null` (unspecified — ambient `Directionality`) | `ltr` | `rtl`. See
  /// [ParagraphTextDirection]'s own doc comment for the same
  /// no-live-rendering-effect caveat [alignment] has, and why
  /// mixed-direction text *within* one paragraph doesn't need this field
  /// at all (it already renders correctly via Flutter's own bidi engine).
  final ParagraphTextDirection? textDirection;

  const ParagraphRecord({
    required this.start,
    required this.end,
    this.headerLevel,
    this.alignment,
    this.textDirection,
  });

  /// Whether `offset` belongs to this paragraph. Inclusive on both
  /// ends — see the containment-convention note on `ParagraphIndex` for
  /// why this differs from `AttributeStore`'s span containment.
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
