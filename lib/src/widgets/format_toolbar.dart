import 'package:flutter/material.dart';

import '../controller/rich_editor_controller.dart';
import '../models/attribute_type.dart';
import '../painters/ruled_lines_painter.dart';
import '../utils/list_prefix.dart';
import 'link_entry_dialog.dart';
import 'tool_button.dart';

/// Every toolbar action — a button tap, a popup-menu selection, a dialog
/// closing — needs to reclaim editor focus afterward; see
/// `RichEditorController.reclaimFocus` for the full reasoning (this used
/// to duplicate that logic locally before it was promoted to public API
/// so hosts building their *own* UI around the editor — an app-bar
/// button, anything outside this toolbar — could reach the same fix).
/// Every toolbar action below funnels through this so nothing here has
/// to remember to call it individually.
void _reclaimEditorFocus(RichEditorController controller) {
  controller.reclaimFocus();
}

/// The editor's formatting toolbar. Grouped into logical clusters
/// (history, structure, inline formatting, color/highlight, insert)
/// separated by generous spacing and light dividers rather than a
/// divider between nearly every button — the old layout treated every
/// 2-3 buttons as its own group, which reads as visual noise rather
/// than structure. `ToolButton` itself is unchanged; this only
/// restructures layout, spacing, and grouping at this level.
class FormatToolbar extends StatelessWidget {
  const FormatToolbar({
    super.key,
    required this.controller,
    required this.showMargin,
    required this.onToggleMargin,
    required this.lineStyle,
    required this.onToggleLineStyle,
    this.onSave,
    this.onLoad,
    this.onToggleFind,
    this.findVisible = false,
  });

  final RichEditorController controller;
  final bool showMargin;
  final VoidCallback onToggleMargin;
  final RuledLineStyle lineStyle;
  final VoidCallback onToggleLineStyle;

  /// Save/Load actions. A host with no notion of "save a note" (e.g. one
  /// that just reads `controller.document` continuously and persists it
  /// on its own schedule) can leave these unset entirely — the
  /// corresponding button is simply left out rather than forcing every
  /// host to wire a no-op callback just to satisfy a required parameter.
  final VoidCallback? onSave;
  final VoidCallback? onLoad;

  /// Toggles the find/replace bar. Omit to leave the button out
  /// entirely (e.g. if the host app puts find/replace somewhere else).
  final VoidCallback? onToggleFind;

  /// Whether the find bar is currently shown — highlights the button.
  final bool findVisible;

  /// Wraps `action` so every toolbar button reclaims editor focus after
  /// firing — see [_reclaimEditorFocus]'s doc comment for why every
  /// single one needs this, not just the menu-based actions.
  VoidCallback _wrap(VoidCallback action) {
    return () {
      action();
      _reclaimEditorFocus(controller);
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            return _FadingScrollRow(
              children: [
                if (onSave != null || onLoad != null) ...[
                  _ToolbarGroup(
                    children: [
                      if (onSave != null)
                        ToolButton(
                          icon: Icons.save_outlined,
                          isActive: false,
                          onPressed: _wrap(onSave!),
                          tooltip: 'Save Note',
                        ),
                      if (onLoad != null)
                        ToolButton(
                          icon: Icons.folder_open_outlined,
                          isActive: false,
                          onPressed: _wrap(onLoad!),
                          tooltip: 'Load Note',
                        ),
                    ],
                  ),
                  _ToolbarDivider(theme: theme),
                ],
                _ToolbarGroup(
                  children: [
                    IconButton(
                      tooltip: 'Undo',
                      icon: Icon(Icons.undo, size: 20),
                      color: controller.canUndo
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                      onPressed: controller.canUndo
                          ? _wrap(controller.undo)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      icon: Icon(Icons.redo, size: 20),
                      color: controller.canRedo
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                      onPressed: controller.canRedo
                          ? _wrap(controller.redo)
                          : null,
                    ),
                    if (onToggleFind != null)
                      ToolButton(
                        icon: Icons.search,
                        isActive: findVisible,
                        onPressed: _wrap(onToggleFind!),
                        tooltip: 'Find & Replace',
                      ),
                  ],
                ),
                _ToolbarDivider(theme: theme),
                _ToolbarGroup(
                  children: [
                    ToolButton(
                      icon: showMargin
                          ? Icons.view_sidebar
                          : Icons.view_sidebar_outlined,
                      isActive: showMargin,
                      onPressed: _wrap(onToggleMargin),
                      tooltip: 'Toggle Margin',
                    ),
                    ToolButton(
                      icon: lineStyle == RuledLineStyle.none
                          ? Icons.grid_off
                          : Icons.grid_on,
                      isActive: lineStyle != RuledLineStyle.none,
                      onPressed: _wrap(onToggleLineStyle),
                      tooltip: 'Cycle Line Style',
                    ),
                  ],
                ),
                _ToolbarDivider(theme: theme),
                // Structure: paragraph-level concerns grouped together —
                // heading level and list type are both "what kind of
                // paragraph is this", the same grouping most editors use.
                _ToolbarGroup(
                  children: [
                    _HeaderMenu(controller: controller),
                    ToolButton(
                      icon: Icons.format_list_bulleted,
                      isActive: controller.isListActive(
                        ParagraphListType.bullet,
                      ),
                      onPressed: _wrap(controller.toggleBulletList),
                      tooltip: 'Bullet List',
                    ),
                    ToolButton(
                      icon: Icons.format_list_numbered,
                      isActive: controller.isListActive(
                        ParagraphListType.numbered,
                      ),
                      onPressed: _wrap(controller.toggleNumberedList),
                      tooltip: 'Numbered List',
                    ),
                    ToolButton(
                      icon: controller.isTaskChecked() == true
                          ? Icons.check_box
                          : Icons.check_box_outlined,
                      isActive: controller.isTaskChecked() != null,
                      onPressed: _wrap(controller.toggleTaskItem),
                      tooltip: 'Checklist',
                    ),
                    ToolButton(
                      icon: Icons.format_indent_decrease,
                      isActive: false,
                      onPressed: _wrap(controller.outdentList),
                      tooltip: 'Decrease Indent',
                    ),
                    ToolButton(
                      icon: Icons.format_indent_increase,
                      isActive: false,
                      onPressed: _wrap(controller.indentList),
                      tooltip: 'Increase Indent',
                    ),
                    _FontSizeControl(controller: controller),
                  ],
                ),
                _ToolbarDivider(theme: theme),
                // Inline formatting.
                _ToolbarGroup(
                  children: [
                    ToolButton(
                      icon: Icons.format_bold,
                      isActive: controller.isAttributeActive(
                        AttributeType.bold,
                      ),
                      onPressed: _wrap(controller.toggleBold),
                      tooltip: 'Bold',
                    ),
                    ToolButton(
                      icon: Icons.format_italic,
                      isActive: controller.isAttributeActive(
                        AttributeType.italic,
                      ),
                      onPressed: _wrap(controller.toggleItalic),
                      tooltip: 'Italic',
                    ),
                    ToolButton(
                      icon: Icons.format_underlined,
                      isActive: controller.isAttributeActive(
                        AttributeType.underline,
                      ),
                      onPressed: _wrap(controller.toggleUnderline),
                      tooltip: 'Underline',
                    ),
                    ToolButton(
                      icon: Icons.format_strikethrough,
                      isActive: controller.isAttributeActive(
                        AttributeType.strikethrough,
                      ),
                      onPressed: _wrap(controller.toggleStrikethrough),
                      tooltip: 'Strikethrough',
                    ),
                  ],
                ),
                _ToolbarDivider(theme: theme),
                // Color/highlight/code.
                _ToolbarGroup(
                  children: [
                    _ColorMenu(controller: controller),
                    ToolButton(
                      icon: Icons.border_color,
                      isActive: controller.isAttributeActive(
                        AttributeType.highlight,
                      ),
                      onPressed: _wrap(controller.toggleHighlight),
                      tooltip: 'Highlight',
                    ),
                    ToolButton(
                      icon: Icons.code,
                      isActive: controller.isAttributeActive(
                        AttributeType.code,
                      ),
                      onPressed: _wrap(controller.toggleCode),
                      tooltip: 'Inline Code',
                    ),
                  ],
                ),
                _ToolbarDivider(theme: theme),
                // Insert + reset — a reset action reads more clearly set
                // apart at the end than folded into the middle.
                _ToolbarGroup(
                  children: [
                    ToolButton(
                      icon: Icons.link,
                      isActive: controller.isAttributeActive(
                        AttributeType.link,
                      ),
                      onPressed: () => _handleInsertLink(context, controller),
                      tooltip: 'Insert Link',
                    ),
                    ToolButton(
                      icon: Icons.format_clear,
                      isActive: false,
                      onPressed: _wrap(controller.clearFormatting),
                      tooltip: 'Clear Formatting',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleInsertLink(
    BuildContext context,
    RichEditorController controller,
  ) async {
    final currentLink =
        controller.activeAttributeValue(AttributeType.link) as String?;
    controller.setSelectionHighlight(controller.selection);
    final url = await showLinkEntryDialog(context, initialUrl: currentLink);
    // setLink runs BEFORE clearing the highlight — setLink reads
    // _currentSelection, which only trusts the highlight while it's
    // still set. Clearing first (the previous order here) meant setLink
    // read whatever controller.selection happened to be with the dialog
    // open — not necessarily the selection the highlight was set up to
    // preserve. Same fix as _HeaderMenu/_ColorMenu below.
    if (url != null) {
      controller.setLink(url);
    }
    controller.setSelectionHighlight(null);
    _reclaimEditorFocus(controller);
  }
}

/// A horizontally scrolling row with a soft fade at each edge hinting
/// there's more content to scroll to — the toolbar has more buttons
/// than fit most phone widths, and a hard-cropped edge with no visual
/// cue reads as "that's all the buttons" rather than "scroll for more".
class _FadingScrollRow extends StatelessWidget {
  const _FadingScrollRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.02, 0.98, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// A cluster of related buttons with consistent internal spacing — the
/// unit `_ToolbarDivider`s separate, instead of individually spacing
/// every single button regardless of which logical group it belongs to.
class _ToolbarGroup extends StatelessWidget {
  const _ToolbarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final child in children)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.0),
            child: child,
          ),
      ],
    );
  }
}

/// A light, low-contrast divider between toolbar groups — thinner and
/// quieter than the default `VerticalDivider`, so it reads as "these are
/// different groups" without competing visually with the icons.
class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: SizedBox(
        height: 24,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _HeaderMenu extends StatelessWidget {
  final RichEditorController controller;

  const _HeaderMenu({required this.controller});

  /// The compact label shown on the trigger itself — 'H1'/'H2' for a
  /// heading, '¶' (a plain-paragraph mark, the same convention word
  /// processors use for "no special style") otherwise. Previously this
  /// button showed only a static icon that turned blue when *some*
  /// heading was active, with no way to tell H1 from H2 (or which
  /// paragraph you were even looking at) without opening the menu —
  /// the current heading level is exactly the kind of thing a user
  /// should be able to see at a glance while the caret moves around.
  static String _labelFor(String? level) => switch (level) {
    'h1' => 'H1',
    'h2' => 'H2',
    _ => '¶',
  };

  @override
  Widget build(BuildContext context) {
    final activeLevel =
        controller.activeAttributeValue(AttributeType.header) as String?;
    final theme = Theme.of(context);
    final color = activeLevel != null
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return PopupMenuButton<String>(
      tooltip: 'Headers',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_size, size: 18, color: color),
            const SizedBox(width: 3),
            Text(
              _labelFor(activeLevel),
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ),
      ),
      onOpened: () => controller.setSelectionHighlight(controller.selection),
      onCanceled: () {
        controller.setSelectionHighlight(null);
        _reclaimEditorFocus(controller);
      },
      onSelected: (val) {
        // setHeader BEFORE clearing the highlight — setHeader reads
        // _currentSelection, which only trusts the highlight while it's
        // still set. Clearing it first (the previous order) meant
        // setHeader read whatever controller.selection happened to be
        // with the menu open — not the selection the highlight exists
        // to preserve. This was the actual cause of "header only
        // applies while the dropdown is open" / "applies to selected
        // text instead of the paragraph": the paragraph-expansion logic
        // itself was correct, it was expanding the wrong selection.
        controller.setHeader(val == 'none' ? null : val);
        controller.setSelectionHighlight(null);
        _reclaimEditorFocus(controller);
      },
      itemBuilder: (context) => [
        _HeaderMenuItem(
          value: 'none',
          label: 'Normal',
          isActive: activeLevel == null,
        ),
        _HeaderMenuItem(
          value: 'h1',
          label: 'Heading 1',
          isActive: activeLevel == 'h1',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        _HeaderMenuItem(
          value: 'h2',
          label: 'Heading 2',
          isActive: activeLevel == 'h2',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}

class _HeaderMenuItem extends PopupMenuItem<String> {
  _HeaderMenuItem({
    required super.value,
    required String label,
    required bool isActive,
    TextStyle? style,
  }) : super(
         child: Row(
           children: [
             Expanded(child: Text(label, style: style)),
             if (isActive)
               const Icon(Icons.check, size: 16, color: Colors.blue),
           ],
         ),
       );
}

class _ColorMenu extends StatelessWidget {
  final RichEditorController controller;

  const _ColorMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];
    // The applied color, if any — same generic-path lookup every other
    // inline attribute already goes through. Shown as a small swatch
    // under the icon rather than tinting the icon itself: the icon's
    // own glyph color needs to stay legible against the toolbar
    // background regardless of which text color happens to be applied
    // (a pale yellow icon-on-icon would be nearly invisible), so the
    // "what color is this" signal is a dedicated dot instead — same
    // "current state visible without opening the menu" fix as the
    // heading/font-size controls above, applied to color for the same
    // reason: none of these had any indication of their current value
    // before this pass.
    final activeColor =
        controller.activeAttributeValue(AttributeType.color) as int?;
    return PopupMenuButton<Color>(
      tooltip: 'Text Color',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.format_color_text,
              size: 20,
              color: Colors.black87,
            ),
            const SizedBox(height: 2),
            Container(
              width: 14,
              height: 3,
              decoration: BoxDecoration(
                color: activeColor != null
                    ? Color(activeColor)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ),
      ),
      onOpened: () => controller.setSelectionHighlight(controller.selection),
      onCanceled: () {
        controller.setSelectionHighlight(null);
        _reclaimEditorFocus(controller);
      },
      onSelected: (color) {
        // Same fix as _HeaderMenu — setColor before clearing the
        // highlight, not after.
        controller.setColor(
          color == const Color(0xff000000) ? null : color.toARGB32(),
        );
        controller.setSelectionHighlight(null);
        _reclaimEditorFocus(controller);
      },
      itemBuilder: (context) => colors
          .map(
            (c) => PopupMenuItem(
              value: c,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// The font-size +/- controls, with the current size shown as a number
/// between them — previously two bare icon buttons with no indication
/// of what size the caret was actually sitting in. Reads
/// `AttributeType.size` the same way `RichEditorController
/// .increaseFontSize`/`decreaseFontSize` already do, so the displayed
/// number always matches what a size change would actually start from.
class _FontSizeControl extends StatelessWidget {
  final RichEditorController controller;

  const _FontSizeControl({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size =
        (controller.activeAttributeValue(AttributeType.size) as num?) ??
        controller.renderer.theme.baseFontSize;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolButton(
          icon: Icons.text_decrease,
          isActive: false,
          tooltip: 'Decrease Font Size',
          onPressed: () {
            controller.decreaseFontSize();
            _reclaimEditorFocus(controller);
          },
        ),
        SizedBox(
          width: 22,
          child: Text(
            '${size.round()}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ToolButton(
          icon: Icons.text_increase,
          isActive: false,
          tooltip: 'Increase Font Size',
          onPressed: () {
            controller.increaseFontSize();
            _reclaimEditorFocus(controller);
          },
        ),
      ],
    );
  }
}
