# lightweight_rich_editor

> [!WARNING]
> This package is currently in active development. APIs may change before the 1.0.0 release.

A performance-focused, lightweight rich-text editor for Flutter with notebook-style ruled lines and a powerful configuration system.

## Features

- **Standard Rich Text Styling**: Bold, Italic, Underline, Strikethrough, inline code.
- **Advanced Styling**: Custom text colors, highlights, font sizes.
- **Structural Elements**: Headings (H1, H2), horizontal rules, bullet/numbered/task lists (with tappable checkboxes).
- **Hyperlinks**: Easy link insertion, editing, and a tap-triggered preview bar.
- **Rich Content Interop**: Intelligent paste support for HTML (from browsers) and Markdown, including native rich-clipboard support on Android, iOS, macOS, Windows, and Linux.
- **Find & Replace**: Built-in find bar with next/previous navigation and replace/replace-all.
- **Notebook Experience**: Customizable horizontal ruled lines and vertical margin lines that stay aligned even when a line wraps or a header is taller than body text.
- **Whole-document alignment/direction**: `textAlign`/`textDirection` for the whole editor, including RTL.
- **Performance First**: Built on top of standard `TextField`/`EditableText` for smooth scrolling and low memory overhead — validated against multi-thousand-paragraph documents.
- **Highly Configurable**: Control colors, fonts, and layout via `RichTextRenderTheme` and `RichEditorStyle`.
- **Serialization**: Save and load documents with high fidelity using `EditorDocument` (JSON-ready).
- **Undo/Redo**: Full history support, including for rich pastes and multi-step edits.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  lightweight_rich_editor: ^0.2.0
```

## Usage

### 1. Quick start

`LightweightRichEditor` bundles the toolbar, editor, and find/replace bar with sensible defaults — the fastest way to drop in a working note editor:

```dart
import 'package:flutter/material.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

class MyEditor extends StatelessWidget {
  const MyEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: const LightweightRichEditor(initialText: 'Hello, world!'),
    );
  }
}
```

Reach the underlying controller — for save/load, programmatic formatting, or listening for changes — via a `GlobalKey<LightweightRichEditorState>`, or by supplying your own `RichEditorController`:

```dart
final key = GlobalKey<LightweightRichEditorState>();

LightweightRichEditor(
  key: key,
  onSave: () => saveToDisk(key.currentState!.controller.document),
);
```

### 2. Composing the pieces yourself

`FormatToolbar`, `RichTextEditor`, and `FindReplaceBar` are also exported individually, for apps that want to place them separately in a layout:

```dart
class MyEditor extends StatefulWidget {
  @override
  State<MyEditor> createState() => _MyEditorState();
}

class _MyEditorState extends State<MyEditor> {
  late final _controller = RichEditorController(text: 'Hello World!');
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormatToolbar(controller: _controller),
        Expanded(
          child: RichTextEditor(
            controller: _controller,
            scrollController: _scrollController,
          ),
        ),
      ],
    );
  }
}
```

### 3. Custom configuration

Customize the editor's text styling and layout via `RichTextRenderTheme` and `RichEditorStyle`:

```dart
final myTheme = RichTextRenderTheme(
  baseFontSize: 18.0,
  highlightColor: Colors.yellow.withValues(alpha: 0.5),
);

final myStyle = RichEditorStyle(
  ruledLineColor: Colors.grey.withValues(alpha: 0.2),
);

final controller = RichEditorController(text: 'Custom Editor', theme: myTheme);
```

Swap themes at runtime (e.g. a dark-mode toggle) by assigning `controller.renderer.theme` directly — no need to recreate the controller:

```dart
setState(() {
  controller.renderer.theme = isDarkMode ? darkTheme : RichTextRenderTheme.standard;
});
```

## Additional information

For a fuller example — dark mode, save/load — check the `example/` folder in the repository.

### Contributions

Contributions are welcome! Please feel free to open issues or pull requests on GitHub.

### License

This project is licensed under the MIT License - see the LICENSE file for details.
