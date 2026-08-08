# lightweight_rich_editor

> [!WARNING]
> This package is currently in active development. APIs may change before the 1.0.0 release.

A performance-focused, lightweight rich-text editor for Flutter with notebook-style ruled lines and a powerful configuration system.

## Features

- **Standard Rich Text Styling**: Bold, Italic, Underline, Strikethrough.
- **Rich Content Interop**: Intelligent paste support for HTML (from browsers) and Markdown, preserving formatting natively.
- **Advanced Styling**: Custom text colors, highlights, font sizes, and inline code.
- **Structural Elements**: Heading support (H1, H2).
- **Hyperlinks**: Easy link insertion and management.
- **Notebook Experience**: Customizable horizontal ruled lines and vertical margin lines.
- **Performance First**: Built on top of standard `EditableText` for smooth scrolling and low memory overhead.
- **Highly Configurable**: Control everything from colors and fonts to history length and behavior via `RichTextRenderTheme` and `RichEditorStyle`.
- **Serialization**: Save and load documents with high fidelity using `EditorDocument` (JSON-ready).

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  lightweight_rich_editor: ^0.1.1
```

## Usage

### 1. Basic Usage

Use the `RichTextEditor` widget along with a `RichEditorController`.

```dart
import 'package:flutter/material.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

class MyEditor extends StatefulWidget {
  @override
  _MyEditorState createState() => _MyEditorState();
}

class _MyEditorState extends State<MyEditor> {
  late final RichEditorController _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = RichEditorController(text: "Hello World!");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RichTextEditor(
        controller: _controller,
        scrollController: _scrollController,
      ),
    );
  }
}
```

### 2. Custom Configuration

Customize the editor's appearance using `RichTextRenderTheme` and `RichEditorStyle`.

```dart
final myTheme = RichTextRenderTheme(
  baseFontSize: 18.0,
  highlightColor: Colors.yellow.withOpacity(0.5),
);

final myStyle = RichEditorStyle(
  ruledLineColor: Colors.grey.withOpacity(0.2),
);

_controller = RichEditorController(
  text: "Custom Editor",
  theme: myTheme,
);
```

### 3. Using the Toolbar

The package provides a `FormatToolbar` that you can easily integrate into your layout.

```dart
Column(
  children: [
    FormatToolbar(
      controller: _controller,
      // ... configuration callbacks
    ),
    Expanded(
      child: RichTextEditor(
        controller: _controller,
        scrollController: _scrollController,
      ),
    ),
  ],
)
```

## Additional information

For more advanced examples, check the `example/` folder in the repository.

### Contributions

Contributions are welcome! Please feel free to open issues or pull requests on GitHub.

### License

This project is licensed under the MIT License - see the LICENSE file for details.
