import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import 'sample_picture.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lightweight Rich Editor Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EditorHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class EditorHomeScreen extends StatefulWidget {
  const EditorHomeScreen({super.key});

  @override
  State<EditorHomeScreen> createState() => _EditorHomeScreenState();
}

class _EditorHomeScreenState extends State<EditorHomeScreen> {
  // Supplied explicitly (rather than left to `LightweightRichEditor` to
  // create internally) because this screen needs to reach it for two
  // things: Save/Load, and swapping themes on dark-mode toggle. A screen
  // that needed neither could just use `LightweightRichEditor(
  // initialText: ...)` with no controller at all.
  late final RichEditorController _controller = _newController();

  static final _sample = '''
# Trip planning

Notes for the **June weekend** away, in *no particular order*. Keep `flutter run` handy, tap the moon for dark mode, or search with the magnifier.

Pack light, book early and bring the big camera.

![The coast at dusk](data:image/png;base64,$samplePictureBase64)

## To pack

- [x] Passport and tickets
- [x] Charger
- [ ] Rain jacket
- [ ] Camera

## Route

1. Train to the coast, leaving 08:10
2. Walk the cliff path to the harbour
3. Dinner at the fish market

## A little code

```dart
final days = ['Fri', 'Sat', 'Sun'];
for (final d in days) {
  print('Packing for ' + d);
}
```

More ideas at [the town guide](https://example.com/guide).

Safe travels, see you on Sunday.
''';

  RichEditorController _newController() {
    return RichEditorController(
      text: '',
      theme: _lightRenderTheme,
    )..imageStore = _MemoryImageStore();
  }

  @override
  void initState() {
    super.initState();
    _controller.pasteMarkdown(_sample);
    _decorate();
  }

  // Colour, highlight and size are not Markdown, so they are applied to
  // ranges of the finished note.
  void _decorate() {
    void style(String word, void Function() apply) {
      final start = _controller.document.text.indexOf(word);
      if (start < 0) return;
      _controller.selection = TextSelection(
        baseOffset: start,
        extentOffset: start + word.length,
      );
      apply();
    }

    style('Pack light', () => _controller.setColor(0xFFE64A19));
    style('book early', _controller.toggleHighlight);
    style('big camera', () => _controller.setSize(22));
    _controller.selection = const TextSelection.collapsed(offset: 0);
  }

  bool _isDarkMode = false;

  ({String text, List<TextAttribute> attributes})? _internalStorage;

  // Rows are 30 px and the headings are sized to fit one row each (see
  // CUSTOMIZATION_GUIDE.md, "Fonts and the ruled grid").
  static const _lightRenderTheme = RichTextRenderTheme(
    lineHeight: 30,
    h1FontSize: 23,
    h2FontSize: 20,
    h3FontSize: 18,
  );

  static const _darkRenderTheme = RichTextRenderTheme(
    textColor: Color(0xFFE6E9EC),
    codeSyntax: CodeSyntaxColors.dark,
    lineHeight: 30,
    h1FontSize: 23,
    h2FontSize: 20,
    h3FontSize: 18,
    highlightColor: Color(0xFF4A148C),
    linkColor: Colors.cyanAccent,
  );

  static const _darkEditorStyle = RichEditorStyle(
    ruledLineColor: Color(0xFF37474F),
    marginLineColor: Color(0xFF455A64),
  );

  void _handleSave() {
    setState(() {
      _internalStorage = (
        text: _controller.document.text,
        attributes: List<TextAttribute>.from(_controller.document.attributes),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note saved to internal memory')),
    );
  }

  void _handleLoad() {
    if (_internalStorage != null) {
      _controller.loadDocument(
        _internalStorage!.text,
        _internalStorage!.attributes,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note restored perfectly')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No saved note found')));
    }
  }

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
      // `TextSpanRenderer.theme` is deliberately mutable for exactly
      // this: reassigning it in place, then letting this `setState`
      // rebuild `LightweightRichEditor` with the matching `editorStyle`,
      // is enough to fully re-theme the editor. No dispose/recreate/
      // reload round-trip of the controller needed -- text, selection,
      // and undo history all stay exactly as they were.
      _controller.renderer.theme = _isDarkMode
          ? _darkRenderTheme
          : _lightRenderTheme;
    });
    // This button lives in this app's own AppBar, outside the library's
    // FormatToolbar -- so it doesn't get the toolbar's built-in focus
    // fix for free. See `RichEditorController.reclaimFocus`'s doc
    // comment: without this, the next character typed after toggling
    // dark mode is silently dropped.
    _controller.reclaimFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // A full dark ThemeData (not just a colour scheme) so the toolbar, find bar
  // and menus pick up light icons and text.
  ThemeData _editorTheme(BuildContext context) {
    if (!_isDarkMode) return Theme.of(context);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isDarkMode
        ? const Color(0xFF263238)
        : const Color(0xFFFDFBF7);
    final textColor = _isDarkMode ? Colors.white70 : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('Notebook Editor', style: TextStyle(color: textColor)),
        backgroundColor: _isDarkMode ? Colors.black : Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: Icon(
              _isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: textColor,
            ),
            onPressed: _toggleDarkMode,
          ),
        ],
      ),
      body: Theme(
        data: _editorTheme(context).copyWith(
          textSelectionTheme: TextSelectionThemeData(
            selectionColor: _isDarkMode
                ? Colors.cyan.withValues(alpha: 0.3)
                : Colors.deepPurple.withValues(alpha: 0.2),
            selectionHandleColor: _isDarkMode ? Colors.cyan : Colors.deepPurple,
            cursorColor: _isDarkMode ? Colors.cyan : Colors.deepPurple,
          ),
        ),
        child: LightweightRichEditor(
          controller: _controller,
          editorStyle: _isDarkMode
              ? _darkEditorStyle
              : RichEditorStyle.standard,
          onSave: _handleSave,
          onLoad: _handleLoad,
        ),
      ),
    );
  }
}

/// Keeps pictures in memory. A real app would write them to disk or a database.
class _MemoryImageStore extends RichImageStore {
  final _pictures = <String, Uint8List>{};
  var _next = 0;

  @override
  Future<String> save(Uint8List bytes) async {
    final id = 'picture-${_next++}';
    _pictures[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> load(String id) async => _pictures[id];
}
