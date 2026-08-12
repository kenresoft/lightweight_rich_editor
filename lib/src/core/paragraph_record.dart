/// One paragraph's boundaries and block-level metadata.
///
/// Deliberately minimal — [headerLevel] is the only populated field.
/// This is not a catch-all block model: new fields (list type, indent
/// level, checked state, alignment) get added only when a concrete,
/// approved feature needs them, following the same "small and
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

  const ParagraphRecord({
    required this.start,
    required this.end,
    this.headerLevel,
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
  }) {
    return ParagraphRecord(
      start: start ?? this.start,
      end: end ?? this.end,
      headerLevel: clearHeaderLevel ? null : (headerLevel ?? this.headerLevel),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ParagraphRecord &&
          other.start == start &&
          other.end == end &&
          other.headerLevel == headerLevel;

  @override
  int get hashCode => Object.hash(start, end, headerLevel);

  @override
  String toString() => 'ParagraphRecord($start, $end, headerLevel: $headerLevel)';
}