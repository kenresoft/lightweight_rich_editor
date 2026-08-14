/// A paragraph's base text direction — `null` means "unspecified" (the
/// live editor's ambient `Directionality`, not necessarily `ltr`).
///
/// Stored on [ParagraphRecord] following exactly the same pattern
/// [ParagraphAlignment] already established: no textual representation
/// (see `ParagraphRecord`'s own doc comment on when a new field belongs
/// here vs. as literal text). Deliberately a new, Flutter-free enum
/// rather than reusing `dart:ui`'s `TextDirection` directly — `TextAttribute`'s
/// own doc comment states the core model layer is deliberately
/// framework-agnostic (colors as ARGB ints, not `Color`), and
/// `ParagraphRecord`/`ParagraphIndex` follow the same rule.
///
/// **This has no live visual effect in the editor today**, for the exact
/// same reason as [ParagraphAlignment]: `RenderEditable` (the single
/// `TextField` this package renders the whole document through) applies
/// exactly one base `textDirection` to the entire widget — per-paragraph
/// base direction cannot render differently within one live-editable
/// field. One thing this does *not* affect, though: mixed-direction text
/// *within* a single paragraph already renders correctly today with zero
/// code from this library — Flutter's text engine runs the Unicode Bidi
/// Algorithm on the actual glyphs regardless of any stored metadata. This
/// value is stored and round-tripped (document JSON save/load, HTML
/// export/import via `dir="rtl"`/`dir="ltr"`) so it survives and is ready
/// for a future renderer, not silently dropped, just not yet visible.
enum ParagraphTextDirection { ltr, rtl }
