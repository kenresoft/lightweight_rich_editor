/// The types of attributes that can be applied to text in the editor.
enum AttributeType {
  /// Bold text.
  bold,

  /// Italic text.
  italic,

  /// Underlined text.
  underline,

  /// Strikethrough text.
  strikethrough,

  /// Highlighted text background.
  highlight,

  /// Custom text color.
  color,

  /// Custom font size.
  size,

  /// Header style (e.g., h1, h2).
  header,

  /// Inline code style.
  code,

  /// Hyperlink.
  link,

  /// Embedded object (e.g., image).
  embed,
}
