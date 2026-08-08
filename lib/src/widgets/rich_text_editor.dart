import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/rich_editor_controller.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/editor_style.dart';
import '../utils/link_launcher.dart';

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

  /// Whether choosing "Open Link" from the selection toolbar (see
  /// [contextMenuBuilder] below) shows an "Open link?" confirmation
  /// before launching it, rather than opening immediately. Defaults to
  /// `true`. Note this is already a two-step, deliberate action
  /// (long-press to select, then explicitly tap the menu item) — this
  /// flag is for teams that want an extra safety net on top of that,
  /// not a substitute for it.
  ///
  /// Has no effect if the controller was constructed with its own
  /// custom `onTapLink` (see `RichEditorController.hasCustomTapHandler`)
  /// — a host that already asked for custom link-activation behavior
  /// is called directly instead.
  final bool confirmBeforeOpeningLinks;

  const RichTextEditor({
    super.key,
    required this.controller,
    required this.scrollController,
    this.showMargin = true,
    this.lineStyle = RuledLineStyle.solid,
    this.editorStyle = RichEditorStyle.standard,
    this.onToggleFind,
    this.confirmBeforeOpeningLinks = true,
  });

  void _openLink(BuildContext context, String url) {
    if (controller.hasCustomTapHandler) {
      controller.renderer.onTapLink?.call(url);
    } else if (confirmBeforeOpeningLinks) {
      confirmAndLaunchLink(context, url);
    } else {
      launchLinkUrl(url);
    }
  }

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
                      // Long-press (the platform's own gesture for
                      // "select word + show the selection toolbar") is
                      // what triggers link activation, via the
                      // "Open Link" button injected below — not a bare
                      // single tap, which stays reserved for cursor
                      // placement. This is also more reliable than
                      // driving activation off `TextField.onTap`:
                      // `contextMenuBuilder` is the framework's actual
                      // supported hook for adding a custom action here,
                      // rather than racing the field's own built-in tap/
                      // double-tap/drag gesture recognizers.
                      contextMenuBuilder: (context, editableTextState) {
                        final selection = editableTextState.textEditingValue.selection;
                        final linkUrl = selection.isValid
                            ? (controller.linkUrlAt(selection.start) ??
                            controller.linkUrlAt(selection.end))
                            : null;

                        if (linkUrl == null) {
                          // No link under the current long-press
                          // selection — identical to the toolbar this
                          // editor always showed before this change.
                          return AdaptiveTextSelectionToolbar.editable(
                            anchors: editableTextState.contextMenuAnchors,
                            clipboardStatus: ClipboardStatus.pasteable,
                            onCopy: () {
                              controller.copy();
                              editableTextState.hideToolbar();
                            },
                            onCut: () {
                              controller.cut();
                              editableTextState.hideToolbar();
                            },
                            onPaste: () => controller.paste(),
                            onSelectAll: () =>
                                editableTextState.selectAll(SelectionChangedCause.toolbar),
                            onLiveTextInput: null,
                            onLookUp: null,
                            onSearchWeb: null,
                            onShare: null,
                          );
                        }

                        // Selection landed on a link: prepend "Open
                        // Link" to the platform's normal button set
                        // (`editableTextState.contextMenuButtonItems`
                        // already computes Cut/Copy/Paste/Select All
                        // exactly as the branch above does by hand) —
                        // additive only, so cut/copy/paste/select-all
                        // on linked text keeps working unchanged.
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: [
                            ContextMenuButtonItem(
                              label: 'Open Link',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                _openLink(context, linkUrl);
                              },
                            ),
                            ...editableTextState.contextMenuButtonItems,
                          ],
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