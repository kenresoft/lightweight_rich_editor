import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/rich_editor_controller.dart';
import '../models/text_attribute.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/editor_style.dart';
import '../utils/rich_clipboard.dart';

/// A rich text editor widget that supports ruled lines and formatted text.
class RichTextEditor extends StatelessWidget {
  /// The controller that manages the text and attributes.
  final RichEditorController controller;

  /// The scroll controller for the editor.
  final ScrollController scrollController;

  /// Whether to show the vertical margin line.
  final bool showMargin;

  /// The style of the horizontal ruled lines.
  final RuledLineStyle lineStyle;

  /// Layout and background painting style.
  final RichEditorStyle editorStyle;

  const RichTextEditor({
    super.key,
    required this.controller,
    required this.scrollController,
    this.showMargin = true,
    this.lineStyle = RuledLineStyle.solid,
    this.editorStyle = RichEditorStyle.standard,
  });

  void _handleCopy() {
    final selection = controller.selection;
    if (selection.isCollapsed) return;

    final selectedText = controller.text.substring(selection.start, selection.end);
    final selectedAttrs = <TextAttribute>[];

    for (final attr in controller.document.attributes) {
      final start = math.max(selection.start, attr.start);
      final end = math.min(selection.end, attr.end);

      if (end > start) {
        selectedAttrs.add(
          TextAttribute(
            start: start - selection.start,
            end: end - selection.start,
            type: attr.type,
            value: attr.value,
          ),
        );
      }
    }

    RichClipboard.instance.setData(selectedText, selectedAttrs);
    Clipboard.setData(ClipboardData(text: selectedText));
  }

  void _handleCut() {
    _handleCopy();
    // Deletes the selection, not "backspace" — deleteSelection reads
    // correctly at the call site instead of relying on deleteBackward's
    // fallback-to-delete-selection behavior for a non-collapsed range.
    controller.deleteSelection();
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final plainText = data?.text;
    if (plainText == null) return;

    if (plainText == RichClipboard.instance.plainText) {
      controller.pasteRichText(
        RichClipboard.instance.plainText,
        RichClipboard.instance.attributes,
      );
    } else {
      controller.insertText(plainText);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately read once, outside any controller-listening scope.
    // Nothing here needs to react to every keystroke/selection change —
    // the theme is effectively static configuration, and the TextField
    // below already listens to `controller` internally (that's what
    // passing `controller: controller` does). Wrapping this whole
    // subtree in a ListenableBuilder on `controller` — which the
    // previous version of this widget did — forces the entire ancestor
    // tree (ruled-line painting, both margin animations) to rebuild on
    // every single selection-drag pointer-move event, fighting
    // RenderEditable's own internal gesture tracking. That's what caused
    // the "selection handles feel stuck / won't track the drag"
    // behavior. Nothing in this widget's own visual output depends on
    // controller state beyond what TextField already handles itself, so
    // nothing here should be listening to it.
    final renderTheme = controller.renderer.theme;

    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) {
            if (intent.collapseSelection) {
              _handleCut();
            } else {
              _handleCopy();
            }
            return null;
          },
        ),
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (intent) {
            _handlePaste();
            return null;
          },
        ),
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: showMargin ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                builder: (context, marginOpacity, child) {
                  // Scoped to exactly what needs it: the ruled-line
                  // painter depends on scroll offset only, so only this
                  // leaf listens to scrollController — not the TextField
                  // above it, and definitely not `controller`.
                  return ListenableBuilder(
                    listenable: scrollController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: RuledLinesPainter(
                          lineHeight: renderTheme.lineHeight,
                          topPadding: editorStyle.paddingTop,
                          scrollOffset: scrollController.hasClients ? scrollController.offset : 0.0,
                          marginOpacity: marginOpacity,
                          lineStyle: lineStyle,
                          marginLineX: editorStyle.marginLineX,
                          lineColor: editorStyle.ruledLineColor,
                          marginColor: editorStyle.marginColor,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: showMargin ? editorStyle.paddingLeftMarginOn : editorStyle.paddingLeftMarginOff,
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                builder: (context, leftPad, _) => Padding(
                  padding: EdgeInsets.only(
                    top: editorStyle.paddingTop,
                    left: leftPad,
                    right: editorStyle.paddingRight,
                    bottom: editorStyle.paddingBottom,
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: controller.focusNode,
                    scrollController: scrollController,
                    maxLines: null,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    selectionHeightStyle: BoxHeightStyle.tight,
                    selectionWidthStyle: BoxWidthStyle.tight,
                    style: TextStyle(
                      fontSize: renderTheme.baseFontSize,
                      height: renderTheme.lineHeight / renderTheme.baseFontSize,
                      color: Colors.black,
                      letterSpacing: 0.2,
                    ),
                    strutStyle: StrutStyle(
                      fontSize: renderTheme.baseFontSize,
                      height: renderTheme.lineHeight / renderTheme.baseFontSize,
                      forceStrutHeight: true,
                      leading: 0.0,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    contextMenuBuilder: (context, editableTextState) {
                      return AdaptiveTextSelectionToolbar.editable(
                        anchors: editableTextState.contextMenuAnchors,
                        clipboardStatus: ClipboardStatus.pasteable,
                        onCopy: () {
                          _handleCopy();
                          editableTextState.copySelection(SelectionChangedCause.toolbar);
                        },
                        onCut: () {
                          _handleCut();
                          editableTextState.cutSelection(SelectionChangedCause.toolbar);
                        },
                        onPaste: () => _handlePaste(),
                        onSelectAll: () => editableTextState.selectAll(SelectionChangedCause.toolbar),
                        onLiveTextInput: null,
                        onLookUp: null,
                        onSearchWeb: null,
                        onShare: null,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}