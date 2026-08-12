import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/rich_editor_controller.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/editor_style.dart';
import '../utils/link_launcher.dart';
import '../utils/list_prefix.dart';
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

class IndentListIntent extends Intent {
  const IndentListIntent();
}

class OutdentListIntent extends Intent {
  const OutdentListIntent();
}

class ToggleBulletListIntent extends Intent {
  const ToggleBulletListIntent();
}

class ToggleNumberedListIntent extends Intent {
  const ToggleNumberedListIntent();
}

class SetHeaderIntent extends Intent {
  const SetHeaderIntent(this.level);
  final String? level;
}

/// Unlike the `CallbackAction`s used for the other shortcuts below, Tab
/// already has a job in Flutter — focus traversal — before this widget
/// ever sees it. A plain `CallbackAction` is *always* enabled once
/// registered, which would swallow Tab unconditionally and break
/// tabbing out of the note editor to whatever's next in the UI, even
/// when the cursor isn't anywhere near a list. Overriding
/// [isActionEnabled] instead means Flutter only dispatches here when
/// there's actually something to indent/outdent; otherwise the intent
/// falls through to the framework's own default Tab handling, same as
/// if this Action didn't exist.
class _IndentListAction extends Action<IndentListIntent> {
  _IndentListAction(this.controller);
  final RichEditorController controller;

  @override
  bool get isActionEnabled =>
      controller.isListActive(ParagraphListType.bullet) || controller.isListActive(ParagraphListType.numbered);

  @override
  Object? invoke(IndentListIntent intent) {
    controller.indentList();
    return null;
  }
}

class _OutdentListAction extends Action<OutdentListIntent> {
  _OutdentListAction(this.controller);
  final RichEditorController controller;

  @override
  bool get isActionEnabled =>
      controller.isListActive(ParagraphListType.bullet) || controller.isListActive(ParagraphListType.numbered);

  @override
  Object? invoke(OutdentListIntent intent) {
    controller.outdentList();
    return null;
  }
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

  /// Makes a list marker act like a single unit for plain Left/Right
  /// caret movement — pressing Left right after a marker jumps to the
  /// very start of the paragraph instead of landing one character into
  /// the marker; pressing Right at the paragraph's start jumps past the
  /// whole marker to the item's actual text. Pure cursor positioning,
  /// no text mutation, so this carries none of the caret-safety risk
  /// virtual/protected markers would — the marker is still ordinary,
  /// individually-navigable text underneath, exactly as it is for
  /// backspace (see `EditingEngine.deleteBackwardEdit`'s doc comment for
  /// the same "closest safe approximation to atomic" reasoning).
  ///
  /// Only a bare arrow press: Shift+Arrow (extending a selection) and
  /// Ctrl/Cmd/Alt+Arrow (word/line jump) keep Flutter's normal behavior
  /// untouched.
  KeyEventResult _handleSmartArrowKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final isLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final isRight = event.logicalKey == LogicalKeyboardKey.arrowRight;
    if (!isLeft && !isRight) return KeyEventResult.ignored;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final hasModifier = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    if (hasModifier) return KeyEventResult.ignored;

    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return KeyEventResult.ignored;

    final caret = selection.start;
    final record = controller.document.paragraphs.paragraphAt(caret);
    if (record == null) return KeyEventResult.ignored;
    final prefixLen = listPrefixLength(controller.document.text, record.start);
    if (prefixLen == 0) return KeyEventResult.ignored;

    if (isLeft && caret == record.start + prefixLen) {
      controller.selection = TextSelection.collapsed(offset: record.start);
      return KeyEventResult.handled;
    }
    if (isRight && caret == record.start) {
      controller.selection = TextSelection.collapsed(offset: record.start + prefixLen);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

    // Assigned directly rather than captured-and-chained with whatever
    // was there before: this widget is stateless and build() can run
    // many times, and re-capturing "the previous handler" on every
    // build would wrap it in a new closure each time — an unbounded
    // chain of nested handlers across rebuilds, not just a style
    // preference. Known, deliberate trade-off: if a host app ever sets
    // its own onKeyEvent on this same controller-owned focusNode, this
    // replaces it rather than composing with it. In practice nothing
    // else should be reaching into a FocusNode this controller itself
    // constructed.
    controller.focusNode.onKeyEvent = _handleSmartArrowKeys;

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
        const SingleActivator(LogicalKeyboardKey.tab): const IndentListIntent(),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): const OutdentListIntent(),
        const SingleActivator(LogicalKeyboardKey.digit8, control: true, shift: true): const ToggleBulletListIntent(),
        const SingleActivator(LogicalKeyboardKey.digit8, meta: true, shift: true): const ToggleBulletListIntent(),
        const SingleActivator(LogicalKeyboardKey.digit7, control: true, shift: true): const ToggleNumberedListIntent(),
        const SingleActivator(LogicalKeyboardKey.digit7, meta: true, shift: true): const ToggleNumberedListIntent(),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true, alt: true): const SetHeaderIntent('h1'),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true, alt: true): const SetHeaderIntent('h1'),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true, alt: true): const SetHeaderIntent('h2'),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true, alt: true): const SetHeaderIntent('h2'),
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
          IndentListIntent: _IndentListAction(controller),
          OutdentListIntent: _OutdentListAction(controller),
          ToggleBulletListIntent: CallbackAction<ToggleBulletListIntent>(
            onInvoke: (intent) {
              controller.toggleBulletList();
              return null;
            },
          ),
          ToggleNumberedListIntent: CallbackAction<ToggleNumberedListIntent>(
            onInvoke: (intent) {
              controller.toggleNumberedList();
              return null;
            },
          ),
          SetHeaderIntent: CallbackAction<SetHeaderIntent>(
            onInvoke: (intent) {
              controller.setHeader(intent.level);
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