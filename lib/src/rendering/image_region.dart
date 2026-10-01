/// One image block laid out in the editor, in document (unscrolled,
/// padding-relative) coordinates: the rows its picture is drawn over.
///
/// The ruled-paper layer paints the picture from this (see `RuledLinesPainter`),
/// the way it paints a code card from a `CodeBlockRegion`.
class ImageRegion {
  const ImageRegion({
    required this.top,
    required this.bottom,
    required this.start,
    required this.end,
    required this.id,
    required this.level,
    required this.rows,
  });

  /// Y of the block's first row top / last row bottom.
  final double top;
  final double bottom;

  /// Document offsets: first row start, last row end.
  final int start;
  final int end;

  /// The picture's id in the host's image store.
  final String id;

  /// The block level string shared by every row (`img:<id>:<instance>`): the
  /// block's identity.
  final String level;

  /// How many rows tall the block is.
  final int rows;

  double get height => bottom - top;

  /// Whether the selection `[start, end]` touches this block.
  bool touchedBy(int selStart, int selEnd) => selStart <= end && selEnd >= start;

  @override
  bool operator ==(Object other) =>
      other is ImageRegion &&
      other.top == top &&
      other.bottom == bottom &&
      other.start == start &&
      other.end == end &&
      other.level == level &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(top, bottom, start, end, level, rows);
}
