/// The closed set of inline formatting kinds the editor supports.
///
/// This is intentionally small and intentionally closed. The product
/// philosophy is "plain text + lightweight inline formatting" — adding a
/// new [AttributeType] should be a deliberate, rare product decision, not
/// something callers can extend ad hoc. Toggle-style attributes (bold,
/// italic, underline, strikethrough, highlight, code) carry no [value];
/// value-style attributes (color, size, link, header) do.
///
/// `bulletList`/`numberedList` were removed entirely — see the git
/// history / earlier design notes: the renderer represented list markers
/// as characters injected into the rendered `TextSpan` that were never
/// part of the underlying document text, which broke `RenderEditable`'s
/// caret math.
///
/// [header] is a different situation: it's **kept in this enum
/// deliberately, and permanently** — not as a migration artifact waiting
/// on one more file. Header formatting is owned by `ParagraphIndex`
/// everywhere it's *live*: editing (`EditingEngine.setHeaderLevel`,
/// `SetHeaderLevelCommand`), rendering (`TextSpanRenderer`), undo, and
/// toolbar state all read/write `ParagraphIndex.headerLevel` and never
/// touch this enum value. [header] survives here purely as the
/// **interchange format** at the boundary with external representations
/// that inherently model headers the same way this enum always did:
/// `HtmlExporter`/`MarkdownExporter` emit `<h1>`/`# ` from a
/// `TextAttribute(type: header, ...)`, and `MarkdownImporter`/
/// `HtmlImporter`/`EditingEngine.pasteRich` construct/consume one on the
/// way in. That's an ordinary, deliberate split between a live model and
/// a wire format, not something to eliminate — doing so would mean
/// restructuring all four of those files to carry header through a
/// separate channel, for no benefit to anything that's actually live.
/// See the block-architecture design notes for the full migration
/// history.
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
}