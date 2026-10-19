# Known limits and extension points

Findings from investigating two features that look like small additions but
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
code paragraphs out unwrapped and clips them to the block - a render-object
change, not a widget change.

## Per-paragraph alignment

Stored, round-tripped through JSON and HTML, **not rendered**. A `TextField` has
one `textAlign`; Flutter's `TextSpan` cannot carry a paragraph style. Faking it
with leading spaces or `WidgetSpan`s corrupts the text model and the ruled-line
metrics. Extension point: the same custom `RenderEditable` as above, applying
the stored `ParagraphRecord.alignment` per paragraph when laying out lines.
