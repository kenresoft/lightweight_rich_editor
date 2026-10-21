## 0.3.1

* Compiles to WebAssembly: the picture download now lives behind a conditional import, so `dart:io` is no longer reachable from the web build. Pasted `data:` pictures work on every platform; fetching a picture from a web address still needs a non-browser platform and returns nothing in a browser, as before.

## 0.3.0

First release on pub.dev. The earlier versions below were development builds and were never
published, so this entry summarises everything the package does.

* `LightweightRichEditor`: toolbar, editor and find bar in one widget. `FormatToolbar`, `RichTextEditor` and
  `FindReplaceBar` are also exported on their own.
* Inline formatting: bold, italic, underline, strikethrough, inline code, text colour, highlight, font size, links.
  Turning a style off at a caret stops it for the text typed next.
* Blocks: headings, bullet, numbered and checklist items (six levels deep, renumbered on every edit, convertible
  between kinds), horizontal rules, fenced code blocks with a language label and syntax colouring, pictures.
* Pictures are kept by id in a `RichImageStore` you provide. They can be pasted, picked, resized, replaced, saved and
  removed, and the importers fetch pictures from pasted pages and Markdown.
* Ruled paper: ruled, dashed, dotted and grid styles, an optional margin line, and lines that follow the measured
  height of each row, so wrapped lines and headings stay on the paper.
* Links: tap to get a bar with Open, Copy, Edit and Remove, an edit sheet, `mailto:` and `tel:` support, and a
  confirmation before opening.
* Find and replace, with Escape to close and Shift+Enter for the previous match.
* Paste of HTML and Markdown, with native rich-clipboard access on Android, iOS, macOS, Windows, Linux and web.
  Export to Markdown and HTML. `HtmlImporter`, `MarkdownImporter` and `MarkdownExporter` are public.
* Undo and redo across rich pastes and multi-step edits.
* Read-only mode, whole-document `textAlign` and `textDirection`, JSON save and load through `EditorDocument`.
* `RichEditorController.reclaimFocus()` for buttons you place outside the toolbar.
* Docs: `CUSTOMIZATION_GUIDE.md` and `EXTENSION_POINTS.md`.

## 0.2.0

* **Whole-document `textAlign`/`textDirection`**: `RichTextEditor` and `LightweightRichEditor` accept `textAlign`
  (default `TextAlign.start`) and `textDirection` (default: the ambient `Directionality`). This is one setting for
  the whole document. `ParagraphAlignment` and `ParagraphTextDirection` are still stored per paragraph but not
  rendered separately; see their doc comments.
* **`LightweightRichEditor`**: a widget bundling the toolbar, editor and find/replace bar with sensible defaults.
  `FormatToolbar`, `RichTextEditor` and `FindReplaceBar` are still exported for apps that want them separately.
* **`RichEditorController.reclaimFocus()`** is now public, so a button outside the toolbar can avoid the
  "next keystroke is dropped" problem the toolbar already handles.
* `FormatToolbar.onSave` and `onLoad` are optional; the buttons are left out when the callback is missing.
* **Smart ruled lines**: lines align to the rendered line boundaries (wrapping, per-paragraph font size) instead of
  a fixed interval.
* **Toolbar state indicators**: the heading and font-size controls show the current value, and the text-colour
  control shows the current colour.
* **Find & Replace**: `Escape` closes the bar, `Shift+Enter` jumps to the previous match.
* **Toolbar focus fix**: toolbar buttons and menus no longer take focus from the editor.
* Horizontal rules: a paragraph of three or more hyphens (`---`) renders as a divider.
* Task list checkboxes, per-paragraph alignment and text-direction metadata, Markdown heading auto-formatting
  (`# `, `## `), and a tap-triggered link preview bar.
* **Breaking**: removed `RichEditorConfig`, unused since 0.1.1 and replaced by `RichEditorStyle` and
  `RichTextRenderTheme`.

## 0.1.1

* **Rich clipboard support**: the package is now a Flutter plugin with native code for Android, iOS and web to
  paste rich text (HTML).
* **Paste detection**: HTML and Markdown are recognised in the system clipboard.
* **HTML importer**: CSS `style` attributes (bold, italic, underline), better whitespace between inline elements,
  and merging of adjacent identical attributes.
* **Markdown importer**: `__` bold markers and nested emphasis.
* Removed the external `clipboard` package in favour of the internal native implementation.

## 0.1.0

* Initial release.
* `RichEditorController` with attribute support.
* `RichEditorConfig` for styling and behaviour.
* `RichTextEditor` widget.
* Ruled lines and margin lines.
* `FormatToolbar`.
* Undo and redo.
* Document serialisation.
