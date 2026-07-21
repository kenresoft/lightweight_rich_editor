import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/rich_text_editing_controller.dart';
import '../models/text_attribute.dart';
import '../painters/ruled_lines_painter.dart';
import '../utils/rich_clipboard.dart';

/// A rich text editor widget that supports ruled lines and formatted text.
class RichTextEditor extends StatelessWidget {
  /// The controller that manages the text and attributes.
  final RichTextEditingController controller;

  /// The scroll controller for the editor.
  final ScrollController scrollController;

  /// Whether to show the vertical margin line.
  final bool showMargin;

  /// The style of the horizontal ruled lines.
  final RuledLineStyle lineStyle;

  /// Creates a [RichTextEditor].
  const RichTextEditor({
    super.key,
    required this.controller,
    required this.scrollController,
    this.showMargin = true,
    this.lineStyle = RuledLineStyle.solid,
  });

  void _handleCopy() {
    final selection = controller.selection;
    if (selection.isCollapsed) return;

    final String selectedText = controller.text.substring(selection.start, selection.end);
    final List<TextAttribute> selectedAttrs = [];

    for (final attr in controller.attributes) {
      final int start = math.max(selection.start, attr.start).toInt();
      final int end = math.min(selection.end, attr.end).toInt();

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
    final selection = controller.selection;
    controller.value = controller.value.copyWith(
      text: controller.text.replaceRange(selection.start, selection.end, ''),
      selection: TextSelection.collapsed(offset: selection.start),
    );
  }

  Future<void> _handlePaste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? plainText = data?.text;

    if (plainText != null) {
      if (plainText == RichClipboard.instance.plainText) {
        controller.insertRichText(
          RichClipboard.instance.plainText,
          RichClipboard.instance.attributes,
        );
      } else {
        controller.insertRichText(plainText, []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = controller.config;

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
                  return ListenableBuilder(
                    listenable: scrollController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: RuledLinesPainter(
                          lineHeight: config.lineHeight,
                          topPadding: config.paddingTop,
                          scrollOffset: scrollController.hasClients ? scrollController.offset : 0.0,
                          marginOpacity: marginOpacity,
                          lineStyle: lineStyle,
                          marginLineX: config.marginLineX,
                          lineColor: config.ruledLineColor,
                          marginColor: config.marginLineColor,
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
                  end: showMargin ? config.paddingLeftMarginOn : config.paddingLeftMarginOff,
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                builder: (context, leftPad, _) => Padding(
                  padding: EdgeInsets.only(
                    top: config.paddingTop,
                    left: leftPad,
                    right: config.paddingRight,
                    bottom: config.paddingBottom,
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
                      fontSize: config.fontSize,
                      height: config.lineHeightMultiplier,
                      color: Colors.black,
                      letterSpacing: 0.2,
                    ),
                    strutStyle: StrutStyle(
                      fontSize: config.fontSize,
                      height: config.lineHeightMultiplier,
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
