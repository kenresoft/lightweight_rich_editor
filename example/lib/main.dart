import 'package:flutter/material.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

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
  late final RichEditorController _controller = RichEditorController(
    text:
        'This is a clean, lightweight rich-text editor.\n\n'
        'Try toggling Dark Mode in the top right to see the configuration system in action!',
    initialAttributes: [
      const TextAttribute(start: 35, end: 41, type: AttributeType.bold),
    ],
    theme: RichTextRenderTheme.standard,
  );

  bool _isDarkMode = false;

  ({String text, List<TextAttribute> attributes})? _internalStorage;

  static const _darkRenderTheme = RichTextRenderTheme(
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
          : RichTextRenderTheme.standard;
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
        data: Theme.of(context).copyWith(
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
