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
  late RichEditorController _controller;
  final ScrollController _scrollController = ScrollController();

  bool _showMarginLine = true;
  RuledLineStyle _lineStyle = RuledLineStyle.solid;
  bool _isDarkMode = false;

  EditorDocument? _internalStorage;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    final config = _isDarkMode ? _darkConfig : RichEditorConfig.standard;
    _controller = RichEditorController(
      text: 'This is a clean, lightweight rich-text editor.\n\n'
          'Try toggling Dark Mode in the top right to see the configuration system in action!',
      initialAttributes: [
        TextAttribute(start: 35, end: 41, type: AttributeType.bold),
      ],
      // config: config,
    );
  }

  static const _darkConfig = RichEditorConfig(
    ruledLineColor: Color(0xFF37474F),
    marginLineColor: Color(0xFF455A64),
    highlightColor: Color(0xFF4A148C),
    linkColor: Colors.cyanAccent,
  );

  void _handleSave() {
    setState(() {
      _internalStorage = _controller.document;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note saved to internal memory')),
    );
  }

  void _handleLoad() {
    if (_internalStorage != null) {
      // _controller.fromDocument(_internalStorage!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note restored perfectly')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved note found')),
      );
    }
  }

  void _toggleMargin() {
    setState(() {
      _showMarginLine = !_showMarginLine;
    });
  }

  void _cycleLineStyle() {
    setState(() {
      if (_lineStyle == RuledLineStyle.solid) {
        _lineStyle = RuledLineStyle.dashed;
      } else if (_lineStyle == RuledLineStyle.dashed) {
        _lineStyle = RuledLineStyle.none;
      } else {
        _lineStyle = RuledLineStyle.solid;
      }
    });
  }

  void _toggleDarkMode() {
    final doc = _controller.document;
    setState(() {
      _isDarkMode = !_isDarkMode;
      _controller.dispose();
      _initController();
      // _controller.fromDocument(doc);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isDarkMode ? const Color(0xFF263238) : const Color(0xFFFDFBF7);
    final textColor = _isDarkMode ? Colors.white70 : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('Notebook Editor', style: TextStyle(color: textColor)),
        backgroundColor: _isDarkMode ? Colors.black : Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode, color: textColor),
            onPressed: _toggleDarkMode,
          ),
        ],
      ),
      body: Column(
        children: [
          FormatToolbar(
            controller: _controller,
            showMargin: _showMarginLine,
            onToggleMargin: _toggleMargin,
            lineStyle: _lineStyle,
            onToggleLineStyle: _cycleLineStyle,
            onSave: _handleSave,
            onLoad: _handleLoad,
          ),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  selectionColor: _isDarkMode ? Colors.cyan.withValues(alpha: 0.3) : Colors.deepPurple.withValues(alpha: 0.2),
                  selectionHandleColor: _isDarkMode ? Colors.cyan : Colors.deepPurple,
                  cursorColor: _isDarkMode ? Colors.cyan : Colors.deepPurple,
                ),
              ),
              child: RichTextEditor(
                controller: _controller,
                scrollController: _scrollController,
                showMargin: _showMarginLine,
                lineStyle: _lineStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
