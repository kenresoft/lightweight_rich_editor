# Known limits and extension points

Findings from investigating three features that look like small additions but
run into the single-`TextField` architecture. None is implemented; each lists
why and the cleanest place to extend.

## Horizontal scrolling inside a code block

Not possible cleanly. The whole document is one `EditableText`; a
`RenderEditable` has one horizontal extent (it wraps at the field width, or with
`maxLines: 1` scrolls the *whole field*). A single paragraph cannot scroll
sideways while its neighbours stay put, and the alternatives each break a hard
requirement: a nested editable per block means a second text-input connection,
second selection and undo model; an overlaid `SingleChildScrollView` of
`Text` cannot be edited or selected as part of the document. Code lines
therefore **wrap** (continuation rows stay inside the block, rules stay hidden).
Extension point: a block-level renderer in a custom `RenderEditable` that lays
code paragraphs out unwrapped and clips them to the block — a render-object
change, not a widget change.

## Syntax highlighting

Not implemented. The fit is good though, because it is purely presentational:
`TextSpanRenderer._codeBlockStyle` already styles every code paragraph uniformly,
and colour changes alone cannot move a glyph, so the ruled grid is safe.
Cleanest design: a `CodeHighlighter` interface (`List<(int start, int end,
TokenKind)> tokenize(String code, String? language)`) on
`RichTextRenderTheme`, run once per code block (not per line, so multi-line
strings and comments work), cached with the existing renderer span cache and
invalidated by the same document revision; token colours from a small
`CodeSyntaxColors` on `RichEditorStyle` with light and dark defaults. Highlighting
is never stored in the document. Keep it dependency-free (a hand-written
tokenizer for ~8 languages is a few hundred lines; a general library such as
`highlight` adds hundreds of KB and a regex engine pass per rebuild).

## Per-paragraph alignment

Stored, round-tripped through JSON and HTML, **not rendered**. A `TextField` has
one `textAlign`; Flutter's `TextSpan` cannot carry a paragraph style. Faking it
with leading spaces or `WidgetSpan`s corrupts the text model and the ruled-line
metrics. Extension point: the same custom `RenderEditable` as above, applying
the stored `ParagraphRecord.alignment` per paragraph when laying out lines.
