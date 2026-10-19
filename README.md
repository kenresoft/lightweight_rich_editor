# lightweight_rich_editor

A rich-text editor for Flutter that draws your note on ruled paper. It is
built on a single `TextField`, so scrolling, selection, IME input and accessibility are the ones Flutter already
gives you.

The API may still change before 1.0.

## What it does

- Bold, italic, underline, strikethrough, inline code, text colour, highlight and font size.
- Headings, bullet, numbered and checklist items (up to six levels deep), horizontal rules.
- Fenced code blocks with a language label and syntax colouring.
- Pictures that sit in the text as blocks of rows. You choose where the bytes are stored.
- Links, with a small bar to open, copy, edit or remove the one you tapped.
- Find and replace.
- Paste of HTML and Markdown (including from a browser), and export to Markdown and HTML.
- Undo and redo.
- Ruled, dashed, dotted and grid paper, with an optional margin line. Lines follow the real height of each row,
  so wrapped lines and headings stay on the paper.
- Read-only mode, whole-document text alignment and direction (RTL works).
- Save and load a document as JSON.

Platforms: Android, iOS, macOS, Windows, Linux and web. Native code is only used for reading and writing rich
text on the clipboard.

## Install

```yaml
dependencies:
  lightweight_rich_editor: ^0.3.0
```

## Use it

`LightweightRichEditor` is the toolbar, the editor and the find bar in one widget:

```dart
import 'package:flutter/material.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

class NoteScreen extends StatelessWidget {
  const NoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: LightweightRichEditor(initialText: 'Hello, world!'),
    );
  }
}
```

To get at the controller, pass your own, or use a key:

```dart
final key = GlobalKey<LightweightRichEditorState>();

LightweightRichEditor(
  key: key,
  onSave: () => save(key.currentState!.controller.document.toJson()),
);
```

### Using the pieces separately

`FormatToolbar`, `RichTextEditor` and `FindReplaceBar` can be placed wherever you like:

```dart
class _NoteState extends State<Note> {
  late final _controller = RichEditorController(text: 'Hello World!');
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormatToolbar(controller: _controller),
        Expanded(
          child: RichTextEditor(
            controller: _controller,
            scrollController: _scroll,
          ),
        ),
      ],
    );
  }
}
```

### Changing how it looks

Text styling is in `RichTextRenderTheme`, the page (padding, ruled lines, margin) is in `RichEditorStyle`:

```dart
final controller = RichEditorController(
  text: 'Custom editor',
  theme: const RichTextRenderTheme(baseFontSize: 18),
);

const style = RichEditorStyle(ruledLineColor: Color(0x33808080));
```

Themes can be swapped while the editor is open, for example for dark mode. The text, selection and undo history
stay as they are:

```dart
controller.renderer.theme = isDark ? darkTheme : RichTextRenderTheme.standard;
```

The package has no fonts, icons or theme of its own. Everything is a value you pass in.
[CUSTOMIZATION_GUIDE.md](CUSTOMIZATION_GUIDE.md) lists them all and covers the awkward cases, such as changing the
font without pushing text off the ruled lines.

## More

- `example/` has a small app with dark mode and save/load.
- [EXTENSION_POINTS.md](EXTENSION_POINTS.md) lists what the editor does not do, and why.
- Bugs and pull requests are welcome on [GitHub](https://github.com/kenresoft/lightweight_rich_editor/issues).

## License

MIT, see [LICENSE](LICENSE). Copyright Kenresoft Technologies Ltd.
