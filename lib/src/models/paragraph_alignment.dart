/// A paragraph's horizontal alignment — `left`/`null` is the default.
///
/// Stored on [ParagraphRecord] following exactly the same pattern
/// `headerLevel` already established: no textual representation, so it
/// can't be derived from the document text the way list-ness is (see
/// `ParagraphRecord`'s own doc comment on when a new field belongs here
/// vs. as literal text).
///
/// **This has no live visual effect in the editor today.** `RenderEditable`
/// (which backs the single `TextField` this package renders the whole
/// document through) applies exactly one `textAlign` to the entire widget;
/// `TextSpan` has no per-run alignment property at all. Per-paragraph
/// alignment cannot be rendered differently within one live-editable
/// `TextField` without replacing that rendering surface entirely, which is
/// out of scope. This value is stored and round-tripped (document
/// JSON save/load, HTML export/import) so it survives and is ready for a
/// future renderer capable of displaying it — not silently dropped, just
/// not yet visible.
enum ParagraphAlignment { left, center, right }
