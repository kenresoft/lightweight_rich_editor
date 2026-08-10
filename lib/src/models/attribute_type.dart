/// The closed set of inline formatting kinds the editor supports.
///
/// This is intentionally small and intentionally closed. The product
/// philosophy is "plain text + lightweight inline formatting" — adding a
/// new [AttributeType] should be a deliberate, rare product decision, not
/// something callers can extend ad hoc. Toggle-style attributes (bold,
/// italic, underline, strikethrough, highlight, code) carry no [value];
/// value-style attributes (color, size, link, header) do.
///
/// `bulletList`/`numberedList` were removed. The renderer represented
/// list markers as characters injected into the rendered `TextSpan` that
/// were never part of the underlying document text. Flutter's
/// `TextEditingController.buildTextSpan` contract requires the rendered
/// span's plain text to match `value.text` exactly, character for
/// character — `EditableText`/`RenderEditable` use that 1:1 mapping to
/// place the caret and resolve selections, with no translation layer.
/// Injected marker characters broke that invariant on every list-bearing
/// line, corrupting cursor placement and selection the moment a note
/// contained a list. A second, independent bug in the paragraph
/// confinement pass (`EditingEngine._confineParagraphScopedAttributes`)
/// made importing a list into O(list lines × document length), which
/// hung on any reasonably sized pasted/imported note, and also dropped
/// list formatting on paragraphs beyond the one immediately following an
/// Enter press.
///
/// Both problems are fundamental to representing list markers as
/// non-document text; a real fix means storing markers as protected,
/// non-editable characters in the document itself (blocking cursor
/// placement/deletion inside them, handling backspace at the boundary,
/// IME composition, copy/paste stripping, serialization) — a new
/// subsystem, not a bug fix. Left as a deliberate future project rather
/// than shipped half-working.
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
  /// paragraph bounds for this type, matching "press H1 anywhere in a
  /// line" behavior rather than requiring the whole line to be selected.
  bool get isParagraphScoped => switch (this) {
    AttributeType.header => true,
    _ => false,
  };
}