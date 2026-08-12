import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/rich_editor_controller.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/editor_style.dart';
import '../utils/link_launcher.dart';
import 'link_entry_dialog.dart';

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
          // Copy/cut/paste are async (they touch the system clipboard
          // via a native plugin) — these now actually await that work
          // instead of firing it and returning immediately. Not proven
          // to be the cause of any specific reported bug, but returning
          // from onInvoke before the clipboard write/read has actually
          // completed is a real correctness gap regardless: any code
          // that assumes "the Action completed" the moment onInvoke
          // returns (haven't found one yet, but a host app's own
          // wrapper reasonably might) would be trusting a lie.
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (intent) async {
              if (intent.collapseSelection) {
                await controller.cut();
              } else {
                await controller.copy();
              }
              return null;
            },
          ),
          PasteTextIntent: CallbackAction<PasteTextIntent>(
            onInvoke: (intent) async {
              await controller.paste();
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
                        // forceStrutHeight was true — it forces every
                        // line's vertical box to this strut's fixed
                        // dimensions regardless of the actual text's
                        // font size on that line. A header's much
                        // larger font (h1/h2) forced into the same
                        // constrained box as body text is a strong,
                        // repeatedly-reported match for "header data is
                        // correct but nothing visibly changes" — three
                        // independent test reports were consistent with
                        // exactly this. Without forceStrutHeight, the
                        // strut still guarantees a *minimum* line
                        // height (so ordinary body text keeps its
                        // current, consistent spacing — ruled-line
                        // alignment is unaffected for any note that
                        // doesn't use headers), but a line can grow
                        // taller when its content needs more room.
                        // Trade-off worth knowing: a header line's
                        // ruled line underneath it may no longer align
                        // perfectly with the notebook-paper grid, since
                        // that line is now taller than a standard row —
                        // only on lines that are actually headers.
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
                        if (!selection.isValid) return const SizedBox.shrink();

                        final linkUrl = controller.linkUrlAt(selection.start);
                        final linkRange = controller.linkRangeAt(selection.start);

                        if (linkUrl == null) {
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

                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: [
                            ContextMenuButtonItem(
                              label: 'Open',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                _openLink(context, linkUrl);
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Edit',
                              onPressed: () async {
                                editableTextState.hideToolbar();
                                if (linkRange != null) {
                                  controller.selection = TextSelection(
                                    baseOffset: linkRange.start,
                                    extentOffset: linkRange.end,
                                  );
                                }
                                final url = await showLinkEntryDialog(context, initialUrl: linkUrl);
                                if (url != null) {
                                  controller.setLink(url);
                                }
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Remove',
                              onPressed: () {
                                editableTextState.hideToolbar();
                                if (linkRange != null) {
                                  controller.selection = TextSelection(
                                    baseOffset: linkRange.start,
                                    extentOffset: linkRange.end,
                                  );
                                }
                                controller.setLink(null);
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