/// A paragraph's base text direction — `null` means "unspecified" (the
/// live editor's ambient `Directionality`, not necessarily `ltr`).
///
/// Stored on [ParagraphRecord] with no textual representation, same as
/// [ParagraphAlignment]. A Flutter-free enum rather than reusing
/// `dart:ui`'s `TextDirection` directly, since the core model layer is
/// deliberately framework-agnostic.
///
/// **Not independently rendered**, for the same reason as
/// [ParagraphAlignment]: the single `TextField` this package renders the
/// whole document through applies one base `textDirection` to its entire
/// contents — see [RichTextEditor.textDirection] for that document-wide
/// setting. This doesn't affect mixed-direction text *within* a single
/// paragraph, which already renders correctly via Flutter's own Unicode
/// Bidi Algorithm regardless of any stored metadata. This value is still
/// stored and round-tripped (document JSON, HTML `dir="rtl"`/`dir="ltr"`)
/// so it survives for a future renderer.
enum ParagraphTextDirection { ltr, rtl }
