import 'package:flutter/material.dart';

import '../controller/rich_editor_controller.dart';
import '../models/text_attribute.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/editor_style.dart';
import '../rendering/render_theme.dart';
import 'find_replace_bar.dart';
import 'format_toolbar.dart';
import 'rich_text_editor.dart';

/// A ready-to-use rich text editor: toolbar, editor, and find/replace
/// bar wired together with sensible defaults.
///
/// [FormatToolbar], [RichTextEditor], and [FindReplaceBar] are also
/// exported individually for hosts that want to place them separately.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('Notes')),
///   body: const LightweightRichEditor(initialText: 'Hello!'),
/// )
/// ```
///
/// Needs a bounded-height ancestor (a [Scaffold]'s `body`, an
/// [Expanded]/[SizedBox]).
///
/// Reach the underlying [RichEditorController] — for save/load,
/// programmatic formatting, or listening for changes — either by
/// supplying your own via [controller] (used as-is, never disposed by
/// this widget) or, if this widget creates one for you, via a
/// `GlobalKey<LightweightRichEditorState>` and
/// `key.currentState!.controller`.
///
/// [editorStyle] is read fresh on every rebuild. [theme] is seed-once:
/// it only sets an internally-created controller's *starting* theme, the
/// same way [initialText] does — later changes to [theme] on rebuild
/// aren't picked up (the controller, not this widget, owns the live
/// theme from then on). To swap themes at runtime, assign
/// `controller.renderer.theme = newTheme` directly. If you supply your
/// own [controller], [theme] is never read by this widget at all.
class LightweightRichEditor extends StatefulWidget {
  /// Supply your own controller if you need to reach it before this
  /// widget builds, or if something else in your app already owns one.
  /// Left `null` (the common case), this widget creates and disposes
  /// one internally.
  final RichEditorController? controller;

  /// Seeds an internally-created [controller]'s starting text. Ignored
  /// if [controller] is supplied.
  final String initialText;

  /// Seeds an internally-created [controller]'s starting attributes.
  /// Ignored if [controller] is supplied.
  final List<TextAttribute> initialAttributes;

  /// Seeds an internally-created [controller]'s text-rendering theme —
  /// see the class doc comment for why this is seed-once, not reactive.
  final RichTextRenderTheme theme;

  /// Ruled-line/margin layout and colors — read fresh every rebuild.
  final RichEditorStyle editorStyle;

  /// Whether the margin line starts visible. A starting point only,
  /// toggled thereafter via the toolbar.
  final bool initialShowMargin;

  /// Ruled-line style (solid/dashed/none) to start with — cycled
  /// thereafter via the toolbar.
  final RuledLineStyle initialLineStyle;

  /// Save/Load toolbar actions. Leaving these unset omits the
  /// corresponding button rather than showing a no-op one.
  final VoidCallback? onSave;
  final VoidCallback? onLoad;

  /// Forwarded to [RichTextEditor.textAlign].
  final TextAlign textAlign;

  /// Forwarded to [RichTextEditor.textDirection].
  final TextDirection? textDirection;

  /// Forwarded to [RichTextEditor.confirmBeforeOpeningLinks].
  final bool confirmBeforeOpeningLinks;

  /// Forwarded to [RichTextEditor.contextMenuBuilder].
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  const LightweightRichEditor({
    super.key,
    this.controller,
    this.initialText = '',
    this.initialAttributes = const [],
    this.theme = RichTextRenderTheme.standard,
    this.editorStyle = RichEditorStyle.standard,
    this.initialShowMargin = true,
    this.initialLineStyle = RuledLineStyle.solid,
    this.onSave,
    this.onLoad,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.confirmBeforeOpeningLinks = true,
    this.contextMenuBuilder,
  });

  @override
  State<LightweightRichEditor> createState() => LightweightRichEditorState();
}

class LightweightRichEditorState extends State<LightweightRichEditor> {
  late final RichEditorController _controller;
  late final bool _ownsController;
  late final ScrollController _scrollController;

  late bool _showMargin = widget.initialShowMargin;
  late RuledLineStyle _lineStyle = widget.initialLineStyle;
  bool _showFindBar = false;

  /// The controller backing this editor, whether supplied via
  /// [LightweightRichEditor.controller] or created internally.
  RichEditorController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        RichEditorController(
          text: widget.initialText,
          initialAttributes: widget.initialAttributes,
          theme: widget.theme,
        );
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // Only disposed if this widget created it — a host-supplied
    // controller stays the host's responsibility.
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _toggleMargin() => setState(() => _showMargin = !_showMargin);

  void _cycleLineStyle() => setState(() {
    _lineStyle = switch (_lineStyle) {
      RuledLineStyle.solid => RuledLineStyle.dashed,
      RuledLineStyle.dashed => RuledLineStyle.none,
      RuledLineStyle.none => RuledLineStyle.solid,
    };
  });

  void _toggleFindBar() => setState(() => _showFindBar = !_showFindBar);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormatToolbar(
          controller: _controller,
          showMargin: _showMargin,
          onToggleMargin: _toggleMargin,
          lineStyle: _lineStyle,
          onToggleLineStyle: _cycleLineStyle,
          onSave: widget.onSave,
          onLoad: widget.onLoad,
          onToggleFind: _toggleFindBar,
          findVisible: _showFindBar,
        ),
        if (_showFindBar)
          FindReplaceBar(
            controller: _controller,
            onClose: () => setState(() => _showFindBar = false),
          ),
        Expanded(
          child: RichTextEditor(
            controller: _controller,
            scrollController: _scrollController,
            showMargin: _showMargin,
            lineStyle: _lineStyle,
            editorStyle: widget.editorStyle,
            onToggleFind: _toggleFindBar,
            textAlign: widget.textAlign,
            textDirection: widget.textDirection,
            confirmBeforeOpeningLinks: widget.confirmBeforeOpeningLinks,
            contextMenuBuilder: widget.contextMenuBuilder,
          ),
        ),
      ],
    );
  }
}
