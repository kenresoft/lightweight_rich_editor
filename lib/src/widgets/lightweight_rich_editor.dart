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
/// [FormatToolbar], [RichTextEditor], and [FindReplaceBar] are exported
/// individually and compose freely for hosts that want to place them
/// separately (in different parts of a layout, with custom widgets
/// between them, etc.) — see this class's own `build()` method for
/// exactly how they fit together, if that's the starting point you need.
/// This widget exists for the much more common case: an app that just
/// wants a working note editor without first discovering that "working
/// note editor" means owning a [RichEditorController], a
/// [ScrollController], and three widgets' worth of toggle state
/// (margin visibility, ruled-line style, find-bar visibility) itself.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('Notes')),
///   body: const LightweightRichEditor(initialText: 'Hello!'),
/// )
/// ```
///
/// Needs a bounded-height ancestor (a [Scaffold]'s `body`, an
/// [Expanded]/[SizedBox] — anything that would already be required to
/// host a bare [RichTextEditor], since that's what this ultimately
/// contains).
///
/// ## Reaching the controller
///
/// Save/load, programmatic formatting, or listening for changes all go
/// through the underlying [RichEditorController] — reach it either by
/// supplying your own via [controller] (this widget will use it as-is
/// and never dispose it — that stays your responsibility) or, if you let
/// this widget create one for you, by holding a
/// `GlobalKey<LightweightRichEditorState>` and reading
/// `key.currentState!.controller`.
///
/// ## `theme` vs `editorStyle`
///
/// [editorStyle] (ruled-line/margin colors and layout) is read fresh on
/// every rebuild, same as passing it straight to [RichTextEditor] — a
/// new value takes effect immediately. [theme] (text styling — the
/// [RichTextRenderTheme] passed to [RichEditorController]) behaves
/// differently *only* when this widget created its own controller: it
/// seeds that controller once, at construction, the same way
/// [initialText] does — later changes to [theme] on rebuild are not
/// picked up automatically, because the controller (not this widget) is
/// what actually owns the live theme from that point on. To swap themes
/// at runtime (e.g. a dark-mode toggle), assign directly:
/// `controller.renderer.theme = newTheme` from inside a `setState` (or
/// equivalent) in the host — [TextSpanRenderer]'s theme field is
/// deliberately mutable for exactly this. If you supply your own
/// [controller], [theme] is never read by this widget at all — the
/// controller you built already carries its own renderer/theme.
class LightweightRichEditor extends StatefulWidget {
  /// Supply your own controller if you need to reach it before this
  /// widget builds (e.g. to attach a listener immediately), or if
  /// something else in your app already owns one. Left `null` (the
  /// common case), this widget creates and disposes one internally.
  final RichEditorController? controller;

  /// Seeds an internally-created [controller]'s starting text. Ignored
  /// if [controller] is supplied — an externally-owned controller's text
  /// is that controller's own business.
  final String initialText;

  /// Seeds an internally-created [controller]'s starting attributes.
  /// Ignored if [controller] is supplied, same as [initialText].
  final List<TextAttribute> initialAttributes;

  /// Seeds an internally-created [controller]'s text-rendering theme —
  /// see the class doc comment's "theme vs editorStyle" section for why
  /// this is seed-once rather than live-reactive, unlike [editorStyle].
  final RichTextRenderTheme theme;

  /// Ruled-line/margin layout and colors — read fresh every rebuild.
  final RichEditorStyle editorStyle;

  /// Whether the margin line and its extra left padding start visible.
  /// Purely a starting point: toggled thereafter via the toolbar's own
  /// button, tracked as this widget's internal state from then on.
  final bool initialShowMargin;

  /// Ruled-line style (solid/dashed/none) to start with — cycled
  /// thereafter via the toolbar, same "starting point only" contract as
  /// [initialShowMargin].
  final RuledLineStyle initialLineStyle;

  /// Save/Load toolbar actions — see [FormatToolbar.onSave]/[onLoad] for
  /// why leaving these unset simply omits the corresponding button
  /// rather than requiring a no-op callback.
  final VoidCallback? onSave;
  final VoidCallback? onLoad;

  /// Forwarded to [RichTextEditor.confirmBeforeOpeningLinks].
  final bool confirmBeforeOpeningLinks;

  /// Forwarded to [RichTextEditor.contextMenuBuilder] — see that field's
  /// doc comment for what the built-in default provides and when you'd
  /// want to override it versus just theming it.
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

  /// The controller backing this editor — whether supplied via
  /// [LightweightRichEditor.controller] or created internally. See the
  /// class doc comment for how to reach this from outside when this
  /// widget owns its own controller.
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
    // Only disposed if this widget created it — a controller the host
    // handed in via `widget.controller` stays the host's responsibility,
    // the same convention `RichEditorController`'s own `focusNode`
    // parameter already follows.
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
            confirmBeforeOpeningLinks: widget.confirmBeforeOpeningLinks,
            contextMenuBuilder: widget.contextMenuBuilder,
          ),
        ),
      ],
    );
  }
}
