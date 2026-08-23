/// A paragraph's horizontal alignment — `left`/`null` is the default.
///
/// Stored on [ParagraphRecord] with no textual representation, same as
/// `headerLevel`.
///
/// **Not independently rendered.** The single `TextField` this package
/// renders the whole document through applies one `textAlign` to its
/// entire contents — see [RichTextEditor.textAlign] for that
/// document-wide setting. Per-paragraph alignment would need replacing
/// that rendering surface entirely. This value is still stored and
/// round-tripped (document JSON, HTML export/import) so it survives for
/// a future renderer, not silently dropped.
enum ParagraphAlignment { left, center, right }
