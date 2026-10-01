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
