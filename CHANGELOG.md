## Unreleased

* **`LightweightRichEditor`**: a new all-in-one widget bundling the
  toolbar, editor, and find/replace bar with sensible defaults — an app
  can now drop in a working note editor without first owning a
  `RichEditorController`, a `ScrollController`, and three widgets' worth
  of toggle state itself. `FormatToolbar`, `RichTextEditor`, and
  `FindReplaceBar` are still exported and compose freely for anyone who
  wants them separately.
* **`RichEditorController.reclaimFocus()`**: promoted from a private
  helper inside `FormatToolbar` to public API, so a host's *own* UI
  around the editor (an app-bar button, anything outside this library's
  toolbar) can fix the same "next keystroke silently dropped" issue the
  toolbar's buttons already handle internally.
* `FormatToolbar.onSave`/`onLoad` are now optional — a host with no
  save/load concept simply omits them instead of wiring no-op callbacks;
  the corresponding buttons are left out rather than shown disabled.
* **Smart ruled lines**: ruled lines now align to actual rendered line
  boundaries (accounting for wrapping and per-paragraph font size, e.g.
  headers) instead of a fixed interval — text no longer drifts onto a
  ruled line on wrapped or heading paragraphs.
* **Toolbar state indicators**: the heading and font-size controls now
  show the current value (`H1`/`H2`/`¶`, and the numeric size) instead of
  requiring the menu to be opened to check; the text-color control shows
  the currently-applied color as a small swatch.
* **Find & Replace**: `Escape` closes the bar, `Shift+Enter` jumps to the
  previous match.
* **Toolbar focus fix**: toolbar buttons and menus no longer drop focus
  from the editor (previously caused a brief visible flicker and, before
  that, dropped keystrokes typed immediately after a toolbar action).
* Horizontal rules: a line of three or more hyphens (`---`) on its own
  paragraph renders as a styled divider.
* Task list checkboxes, per-paragraph alignment/text-direction metadata
  (stored, not yet independently rendered), Markdown header
  auto-formatting (`# ` / `## `), and a tap-triggered link preview bar.
* **Breaking**: removed `RichEditorConfig`, unused since 0.1.1 and fully
  superseded by `RichEditorStyle` (layout/ruled lines) and
  `RichTextRenderTheme` (text styling).

## 0.1.1

* **Rich Clipboard Support**: Converted package to a Flutter Plugin with native implementations for Android, iOS, and Web to support rich-text (HTML) paste.
* **Heuristic Paste Detection**: Added smart detection for HTML and Markdown in the system clipboard when pasting.
* **HTML Importer Improvements**: 
    * Support for CSS `style` attributes (bold, italic, underline).
    * Better whitespace normalization between inline elements.
    * Automatic merging of contiguous identical attributes.
* **Markdown Importer Improvements**: 
    * Support for `__` bold markers.
    * Robust handling of nested emphasis markers.
* Removed external `clipboard` package dependency in favor of native internal implementation.

## 0.1.0

* Initial release.
* Core RichEditorController with attribute support.
* Flexible RichEditorConfig system for styling and behavior.
* Unopinionated RichTextEditor widget.
* Notebook-style ruled lines and margin lines.
* FormatToolbar for easy styling.
* Undo/Redo history.
* Serialization/Deserialization of documents.
