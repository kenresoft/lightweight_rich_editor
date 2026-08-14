import 'package:flutter/material.dart';

import '../controller/rich_editor_controller.dart';
import '../models/attribute_type.dart';
import '../painters/ruled_lines_painter.dart';
import '../utils/list_prefix.dart';
import 'link_entry_dialog.dart';
import 'tool_button.dart';

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
    required this.onSave,
    required this.onLoad,
    this.onToggleFind,
    this.findVisible = false,
  });

  final RichEditorController controller;
  final bool showMargin;
  final VoidCallback onToggleMargin;
  final RuledLineStyle lineStyle;
  final VoidCallback onToggleLineStyle;
  final VoidCallback onSave;
  final VoidCallback onLoad;

  /// Toggles the find/replace bar. Omit to leave the button out
  /// entirely (e.g. if the host app puts find/replace somewhere else).
  final VoidCallback? onToggleFind;

  /// Whether the find bar is currently shown — highlights the button.
  final bool findVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            return _FadingScrollRow(
              children: [
                _ToolbarGroup(children: [
                  ToolButton(icon: Icons.save_outlined, isActive: false, onPressed: onSave, tooltip: 'Save Note'),
                  ToolButton(icon: Icons.folder_open_outlined, isActive: false, onPressed: onLoad, tooltip: 'Load Note'),
                ]),
                _ToolbarDivider(theme: theme),
                _ToolbarGroup(children: [
                  IconButton(
                    tooltip: 'Undo',
                    icon: Icon(Icons.undo, size: 20),
                    color: controller.canUndo ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    onPressed: controller.canUndo ? controller.undo : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    icon: Icon(Icons.redo, size: 20),
                    color: controller.canRedo ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    onPressed: controller.canRedo ? controller.redo : null,
                  ),
                  if (onToggleFind != null)
                    ToolButton(
                      icon: Icons.search,
                      isActive: findVisible,
                      onPressed: onToggleFind!,
                      tooltip: 'Find & Replace',
                    ),
                ]),
                _ToolbarDivider(theme: theme),
                _ToolbarGroup(children: [
                  ToolButton(
                    icon: showMargin ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                    isActive: showMargin,
                    onPressed: onToggleMargin,
                    tooltip: 'Toggle Margin',
                  ),
                  ToolButton(
                    icon: lineStyle == RuledLineStyle.none ? Icons.grid_off : Icons.grid_on,
                    isActive: lineStyle != RuledLineStyle.none,
                    onPressed: onToggleLineStyle,
                    tooltip: 'Cycle Line Style',
                  ),
                ]),
                _ToolbarDivider(theme: theme),
                // Structure: paragraph-level concerns grouped together —
                // heading level and list type are both "what kind of
                // paragraph is this", the same grouping most editors use.
                _ToolbarGroup(children: [
                  _HeaderMenu(controller: controller),
                  ToolButton(
                    icon: Icons.format_list_bulleted,
                    isActive: controller.isListActive(ParagraphListType.bullet),
                    onPressed: controller.toggleBulletList,
                    tooltip: 'Bullet List',
                  ),
                  ToolButton(
                    icon: Icons.format_list_numbered,
                    isActive: controller.isListActive(ParagraphListType.numbered),
                    onPressed: controller.toggleNumberedList,
                    tooltip: 'Numbered List',
                  ),
                  ToolButton(
                    icon: controller.isTaskChecked() == true
                        ? Icons.check_box
                        : Icons.check_box_outlined,
                    isActive: controller.isTaskChecked() != null,
                    onPressed: controller.toggleTaskItem,
                    tooltip: 'Checklist',
                  ),
                  ToolButton(
                    icon: Icons.format_indent_decrease,
                    isActive: false,
                    onPressed: controller.outdentList,
                    tooltip: 'Decrease Indent',
                  ),
                  ToolButton(
                    icon: Icons.format_indent_increase,
                    isActive: false,
                    onPressed: controller.indentList,
                    tooltip: 'Increase Indent',
                  ),
                  ToolButton(
                    icon: Icons.text_increase,
                    isActive: false,
                    onPressed: controller.increaseFontSize,
                    tooltip: 'Increase Font Size',
                  ),
                  ToolButton(
                    icon: Icons.text_decrease,
                    isActive: false,
                    onPressed: controller.decreaseFontSize,
                    tooltip: 'Decrease Font Size',
                  ),
                ]),
                _ToolbarDivider(theme: theme),
                // Inline formatting.
                _ToolbarGroup(children: [
                  ToolButton(icon: Icons.format_bold, isActive: controller.isAttributeActive(AttributeType.bold), onPressed: controller.toggleBold, tooltip: 'Bold'),
                  ToolButton(icon: Icons.format_italic, isActive: controller.isAttributeActive(AttributeType.italic), onPressed: controller.toggleItalic, tooltip: 'Italic'),
                  ToolButton(icon: Icons.format_underlined, isActive: controller.isAttributeActive(AttributeType.underline), onPressed: controller.toggleUnderline, tooltip: 'Underline'),
                  ToolButton(
                    icon: Icons.format_strikethrough,
                    isActive: controller.isAttributeActive(AttributeType.strikethrough),
                    onPressed: controller.toggleStrikethrough,
                    tooltip: 'Strikethrough',
                  ),
                ]),
                _ToolbarDivider(theme: theme),
                // Color/highlight/code.
                _ToolbarGroup(children: [
                  _ColorMenu(controller: controller),
                  ToolButton(icon: Icons.border_color, isActive: controller.isAttributeActive(AttributeType.highlight), onPressed: controller.toggleHighlight, tooltip: 'Highlight'),
                  ToolButton(icon: Icons.code, isActive: controller.isAttributeActive(AttributeType.code), onPressed: controller.toggleCode, tooltip: 'Inline Code'),
                ]),
                _ToolbarDivider(theme: theme),
                // Insert + reset — a reset action reads more clearly set
                // apart at the end than folded into the middle.
                _ToolbarGroup(children: [
                  ToolButton(
                    icon: Icons.link,
                    isActive: controller.isAttributeActive(AttributeType.link),
                    onPressed: () => _handleInsertLink(context, controller),
                    tooltip: 'Insert Link',
                  ),
                  ToolButton(icon: Icons.format_clear, isActive: false, onPressed: controller.clearFormatting, tooltip: 'Clear Formatting'),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleInsertLink(BuildContext context, RichEditorController controller) async {
    final currentLink = controller.activeAttributeValue(AttributeType.link) as String?;
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
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
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
      children: [for (final child in children) Padding(padding: const EdgeInsets.symmetric(horizontal: 1.0), child: child)],
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
        child: VerticalDivider(width: 1, thickness: 1, color: theme.colorScheme.outlineVariant),
      ),
    );
  }
}

class _HeaderMenu extends StatelessWidget {
  final RichEditorController controller;

  const _HeaderMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    final activeLevel = controller.activeAttributeValue(AttributeType.header) as String?;
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      tooltip: 'Headers',
      icon: Icon(
        Icons.format_size,
        size: 20,
        color: activeLevel != null ? theme.colorScheme.primary : theme.colorScheme.onSurface,
      ),
      onOpened: () => controller.setSelectionHighlight(controller.selection),
      onCanceled: () => controller.setSelectionHighlight(null),
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
        if (isActive) const Icon(Icons.check, size: 16, color: Colors.blue),
      ],
    ),
  );
}

class _ColorMenu extends StatelessWidget {
  final RichEditorController controller;

  const _ColorMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = [Colors.black, Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple];
    return PopupMenuButton<Color>(
      tooltip: 'Text Color',
      icon: const Icon(Icons.format_color_text, size: 20, color: Colors.black87),
      onOpened: () => controller.setSelectionHighlight(controller.selection),
      onCanceled: () => controller.setSelectionHighlight(null),
      onSelected: (color) {
        // Same fix as _HeaderMenu — setColor before clearing the
        // highlight, not after.
        controller.setColor(color == const Color(0xff000000) ? null : color.toARGB32());
        controller.setSelectionHighlight(null);
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