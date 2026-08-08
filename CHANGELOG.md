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
