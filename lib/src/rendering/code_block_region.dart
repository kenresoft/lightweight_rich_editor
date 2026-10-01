/// A run of consecutive code lines laid out in the editor, in document
/// (unscrolled, padding-relative) coordinates — what the ruled-paper layer
/// paints the block's background from.
class CodeBlockRegion {
  const CodeBlockRegion({
    required this.top,
    required this.bottom,
    required this.start,
    required this.end,
    this.language,
  });

  /// Y of the block's first line top / last line bottom.
  final double top;
  final double bottom;

  /// Document offsets of the block's text: first line start, last line end.
  final int start;
  final int end;

  /// Normalized language label, or `null`.
  final String? language;

  @override
  bool operator ==(Object other) =>
      other is CodeBlockRegion &&
      other.top == top &&
      other.bottom == bottom &&
      other.start == start &&
      other.end == end &&
      other.language == language;

  @override
  int get hashCode => Object.hash(top, bottom, start, end, language);
}

/// An empty paragraph (a blank line) and where it sits, so the ruled-paper layer
/// can mark it when a selection runs across it: a text field paints nothing for
/// a selected line break that has no glyphs.
class BlankLineRegion {
  const BlankLineRegion({required this.offset, required this.top, required this.bottom});

  /// Document offset of the blank paragraph (its own line break is the
  /// character at this offset).
  final int offset;
  final double top;
  final double bottom;
}
