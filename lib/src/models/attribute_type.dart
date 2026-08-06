/// The closed set of inline formatting kinds the editor supports.
///
/// This is intentionally small and intentionally closed. The product
/// philosophy is "plain text + lightweight inline formatting" — adding a
/// new [AttributeType] should be a deliberate, rare product decision, not
/// something callers can extend ad hoc. Toggle-style attributes (bold,
/// italic, underline, strikethrough, highlight, code) carry no [value];
/// value-style attributes (color, size, link, header) do.
enum AttributeType {
  bold,
  italic,
  underline,
  strikethrough,
  highlight,
  code,
  color,
  size,
  link,
  header;

  /// Whether this attribute is a simple on/off toggle with no payload.
  bool get isToggle => switch (this) {
    AttributeType.bold ||
    AttributeType.italic ||
    AttributeType.underline ||
    AttributeType.strikethrough ||
    AttributeType.highlight ||
    AttributeType.code =>
    true,
    AttributeType.color ||
    AttributeType.size ||
    AttributeType.link ||
    AttributeType.header =>
    false,
  };

  /// Whether this attribute applies to the whole paragraph containing the
  /// selection rather than the selected characters — currently only
  /// [header]. `EditingEngine.applyAttribute` expands the edit range to
  /// paragraph bounds for these, matching "press H1 anywhere in a line"
  /// behavior rather than requiring the whole line to be selected.
  bool get isParagraphScoped => this == AttributeType.header;
}