import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/rich_editor_controller.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/editor_style.dart';

/// Toggles bold on the current selection. No Flutter default binding —
/// registered below via [Shortcuts].
class ToggleBoldIntent extends Intent {
  const ToggleBoldIntent();
}

class ToggleItalicIntent extends Intent {
  const ToggleItalicIntent();
}

class ToggleUnderlineIntent extends Intent {
  const ToggleUnderlineIntent();
}

class ToggleFindIntent extends Intent {
  const ToggleFindIntent();
}

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

  /// Called when the user presses a "find" shortcut (e.g. Ctrl+F).
  final VoidCallback? onToggleFind;

  const RichTextEditor({
    super.key,
    required this.controller,
    required this.scrollController,
    this.showMargin = true,
    this.lineStyle = RuledLineStyle.solid,
    this.editorStyle = RichEditorStyle.standard,
    this.onToggleFind,
  });

  @override
  Widget build(BuildContext context) {
    // Deliberately read once, outside any controller-listening scope.
    // Nothing here needs to react to every keystroke/selection change —
    // the theme is effectively static configuration, and the TextField
    // below already listens to `controller` internally (that's what
    // passing `controller: controller` does). Wrapping this whole
    // subtree in a ListenableBuilder on `controller` — which a previous
    // version of this widget did — forces the entire ancestor tree
    // (ruled-line painting, both margin animations) to rebuild on every
    // single selection-drag pointer-move event, fighting RenderEditable's
    // own internal gesture tracking, which is what caused selection
    // handles to feel stuck instead of tracking the drag smoothly.
    // Nothing in this widget's own visual output depends on controller
    // state beyond what TextField already handles itself, so nothing
    // here should be listening to it.
    final renderTheme = controller.renderer.theme;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): const ToggleBoldIntent(),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): const ToggleBoldIntent(),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): const ToggleItalicIntent(),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): const ToggleItalicIntent(),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): const ToggleUnderlineIntent(),
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true): const ToggleUnderlineIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): const ToggleFindIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): const ToggleFindIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ToggleBoldIntent: CallbackAction<ToggleBoldIntent>(
            onInvoke: (intent) {
              controller.toggleBold();
              return null;
            },
          ),
          ToggleItalicIntent: CallbackAction<ToggleItalicIntent>(
            onInvoke: (intent) {
              controller.toggleItalic();
              return null;
            },
          ),
          ToggleUnderlineIntent: CallbackAction<ToggleUnderlineIntent>(
            onInvoke: (intent) {
              controller.toggleUnderline();
              return null;
            },
          ),
          ToggleFindIntent: CallbackAction<ToggleFindIntent>(
            onInvoke: (intent) {
              onToggleFind?.call();
              return null;
            },
          ),
          // Flutter's TextField has its own default Ctrl/Cmd+Z / Shift+Z
          // key bindings already active (registered above this widget,
          // at the app level) — without overriding the *intents* here,
          // they'd drive Flutter's own internal text-editing undo, which
          // knows nothing about our HistoryManager or AttributeStore and
          // would desync formatting from text the moment it fired.
          // Overriding the intent (not the key binding) redirects the
          // existing shortcut to our own undo/redo instead.
          UndoTextIntent: CallbackAction<UndoTextIntent>(
            onInvoke: (intent) {
              controller.undo();
              return null;
            },
          ),
          RedoTextIntent: CallbackAction<RedoTextIntent>(
            onInvoke: (intent) {
              controller.redo();
              return null;
            },
          ),
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (intent) {
              if (intent.collapseSelection) {
                controller.cut();
              } else {
                controller.copy();
              }
              return null;
            },
          ),
          PasteTextIntent: CallbackAction<PasteTextIntent>(
            onInvoke: (intent) {
              controller.paste();
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
                    // painter depends on scroll offset only.
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
                            controller.copy();
                            editableTextState.copySelection(SelectionChangedCause.toolbar);
                          },
                          onCut: () {
                            controller.cut();
                            editableTextState.cutSelection(SelectionChangedCause.toolbar);
                          },
                          onPaste: () => controller.paste(),
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
      ),
    );
  }
}