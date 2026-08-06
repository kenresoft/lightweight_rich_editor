import 'package:flutter/material.dart';

import '../controller/rich_editor_controller.dart';
import '../models/attribute_type.dart';
import '../painters/ruled_lines_painter.dart';
import 'tool_button.dart';

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
  });

  final RichEditorController controller;
  final bool showMargin;
  final VoidCallback onToggleMargin;
  final RuledLineStyle lineStyle;
  final VoidCallback onToggleLineStyle;
  final VoidCallback onSave;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ToolButton(icon: Icons.save, isActive: false, onPressed: onSave, tooltip: 'Save Note'),
                ToolButton(icon: Icons.folder_open, isActive: false, onPressed: onLoad, tooltip: 'Load Note'),
                const VerticalDivider(indent: 8, endIndent: 8),
                IconButton(
                  tooltip: 'Undo',
                  icon: Icon(Icons.undo, size: 20, color: controller.canUndo ? Colors.black87 : Colors.grey[400]),
                  onPressed: controller.canUndo ? controller.undo : null,
                ),
                IconButton(
                  tooltip: 'Redo',
                  icon: Icon(Icons.redo, size: 20, color: controller.canRedo ? Colors.black87 : Colors.grey[400]),
                  onPressed: controller.canRedo ? controller.redo : null,
                ),
                const VerticalDivider(indent: 8, endIndent: 8),
                ToolButton(icon: showMargin ? Icons.view_sidebar : Icons.view_sidebar_outlined, isActive: showMargin, onPressed: onToggleMargin, tooltip: 'Toggle Margin'),
                ToolButton(
                  icon: lineStyle == RuledLineStyle.none ? Icons.grid_off : Icons.grid_on,
                  isActive: lineStyle != RuledLineStyle.none,
                  onPressed: onToggleLineStyle,
                  tooltip: 'Cycle Line Style',
                ),
                const VerticalDivider(indent: 8, endIndent: 8),
                _HeaderMenu(controller: controller),
                const VerticalDivider(indent: 8, endIndent: 8),
                ToolButton(icon: Icons.format_bold, isActive: controller.isAttributeActive(AttributeType.bold), onPressed: () => controller.toggleBold, tooltip: 'Bold'),
                ToolButton(icon: Icons.format_italic, isActive: controller.isAttributeActive(AttributeType.italic), onPressed: () => controller.toggleItalic(), tooltip: 'Italic'),
                ToolButton(icon: Icons.format_underlined, isActive: controller.isAttributeActive(AttributeType.underline), onPressed: () => controller.toggleUnderline(), tooltip: 'Underline'),
                ToolButton(
                  icon: Icons.format_strikethrough,
                  isActive: controller.isAttributeActive(AttributeType.strikethrough),
                  onPressed: () => controller.toggleStrikethrough(),
                  tooltip: 'Strikethrough',
                ),
                const VerticalDivider(indent: 8, endIndent: 8),
                _ColorMenu(controller: controller),
                ToolButton(icon: Icons.border_color, isActive: controller.isAttributeActive(AttributeType.highlight), onPressed: () => controller.toggleHighlight(), tooltip: 'Highlight'),
                ToolButton(icon: Icons.code, isActive: controller.isAttributeActive(AttributeType.code), onPressed: () => controller.toggleCode(), tooltip: 'Inline Code'),
                const VerticalDivider(indent: 8, endIndent: 8),
                ToolButton(icon: Icons.link, isActive: controller.isAttributeActive(AttributeType.link), onPressed: () => _showLinkDialog(context, controller), tooltip: 'Insert Link'),
                ToolButton(icon: Icons.format_clear, isActive: false, onPressed: controller.clearFormatting, tooltip: 'Clear Formatting'),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showLinkDialog(BuildContext context, RichEditorController controller) {
    final TextEditingController urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insert Link'),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (urlController.text.isNotEmpty) {
                controller.setLink(urlController.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Insert'),
          ),
        ],
      ),
    );
  }
}

class _HeaderMenu extends StatelessWidget {
  final RichEditorController controller;

  const _HeaderMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Headers',
      icon: const Icon(Icons.format_size, size: 20, color: Colors.black87),
      onSelected: (val) => controller.setHeader(val == 'none' ? null : val),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'none', child: Text('Normal')),
        const PopupMenuItem(
          value: 'h1',
          child: Text('Heading 1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        const PopupMenuItem(
          value: 'h2',
          child: Text('Heading 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ],
    );
  }
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
      onSelected: (color) => controller.setColor(color == Color(0xff000000) ? null : color.toARGB32()),
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
