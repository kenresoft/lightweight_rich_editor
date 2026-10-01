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
    this.firstLineRight = 0.0,
    this.previousLineRight = 0.0,
    this.firstRowBottom = 0.0,
    this.lastRowTop = 0.0,
    this.lastLineRight = 0.0,
  });

  /// Y of the block's first line top / last line bottom.
  final double top;
  final double bottom;

  /// Document offsets of the block's text: first line start, last line end.
  final int start;
  final int end;

  /// Normalized language label, or `null`.
  final String? language;

  /// Right edge (x, text-area relative) of the text on the block's first row,
  /// and of the last row of whatever is directly above it (0 when that row is
  /// blank or there is none). The block's label chip uses them to avoid sitting
  /// on top of text.
  final double firstLineRight;
  final double previousLineRight;

  /// Y of the bottom of the block's first row and the top of its last row, and
  /// the right edge of the text on the last row: where the chip can sit inside
  /// the card without covering code.
  final double firstRowBottom;
  final double lastRowTop;
  final double lastLineRight;

  @override
  bool operator ==(Object other) =>
      other is CodeBlockRegion &&
      other.top == top &&
      other.bottom == bottom &&
      other.start == start &&
      other.end == end &&
      other.language == language &&
      other.firstLineRight == firstLineRight &&
      other.previousLineRight == previousLineRight &&
      other.firstRowBottom == firstRowBottom &&
      other.lastRowTop == lastRowTop &&
      other.lastLineRight == lastLineRight;

  @override
  int get hashCode => Object.hash(top, bottom, start, end, language, firstLineRight, previousLineRight, firstRowBottom, lastRowTop, lastLineRight);
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
