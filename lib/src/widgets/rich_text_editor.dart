import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/rich_editor_controller.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/editor_style.dart';
import '../search/search_index.dart';
import '../utils/link_launcher.dart';
import '../utils/list_prefix.dart';
import 'link_entry_dialog.dart';
import 'link_preview_bar.dart';

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

class ToggleTaskItemIntent extends Intent {
  const ToggleTaskItemIntent();
}

class SetHeaderIntent extends Intent {
  const SetHeaderIntent(this.level);
  final String? level;
}

// Overrides isActionEnabled (rather than a plain CallbackAction, always
// enabled) so Tab only indents/outdents near a list, falling through to
// Flutter's default focus-traversal Tab handling everywhere else.
class _IndentListAction extends Action<IndentListIntent> {
  _IndentListAction(this.controller);
  final RichEditorController controller;

  @override
  bool get isActionEnabled =>
      controller.isListActive(ParagraphListType.bullet) ||
      controller.isListActive(ParagraphListType.numbered);

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
      controller.isListActive(ParagraphListType.bullet) ||
      controller.isListActive(ParagraphListType.numbered);

  @override
  Object? invoke(OutdentListIntent intent) {
    controller.outdentList();
    return null;
  }
}

// Shared by the real `TextField` (via `DefaultTextHeightBehavior`) and
// `TextSpanRenderer.lineBottomOffsets`'s parallel layout — both must use
// the same value or they'll disagree about where a line's glyphs fall.
const _kTextHeightBehavior = TextHeightBehavior(
  leadingDistribution: TextLeadingDistribution.even,
);

/// Renders nothing — its only job is scrolling [scrollController] so the
/// current search match stays visible after Find/Next/Previous.
///
/// Needed because `findNext`/`findPrevious` move `controller.selection`
/// programmatically, and `EditableText`'s own bring-into-view behavior
/// only reacts to a selection change that comes from an actual gesture
/// on the field itself.
class _ScrollToCurrentMatch extends StatefulWidget {
  const _ScrollToCurrentMatch({
    required this.controller,
    required this.scrollController,
    required this.maxWidth,
    required this.style,
    required this.strutStyle,
    required this.topPadding,
    required this.textDirection,
  });

  final RichEditorController controller;
  final ScrollController scrollController;
  final double maxWidth;
  final TextStyle style;
  final StrutStyle strutStyle;
  final double topPadding;
  final TextDirection textDirection;

  @override
  State<_ScrollToCurrentMatch> createState() => _ScrollToCurrentMatchState();
}

class _ScrollToCurrentMatchState extends State<_ScrollToCurrentMatch> {
  SearchMatch? _lastMatch;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _ScrollToCurrentMatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final match = widget.controller.search.currentMatch;
    if (match == _lastMatch) return;
    _lastMatch = match;
    if (match == null) return;
    if (!widget.scrollController.hasClients) return;

    final position = widget.scrollController.position;
    final y =
        widget.topPadding +
        widget.controller.renderer.offsetYFor(
          widget.controller.document,
          match.start,
          maxWidth: widget.maxWidth,
          style: widget.style,
          strutStyle: widget.strutStyle,
          textHeightBehavior: _kTextHeightBehavior,
          textDirection: widget.textDirection,
        );

    // Already comfortably on screen -- leave the scroll position alone
    // rather than re-centering on every Next/Previous.
    const edgeMargin = 24.0;
    final viewportTop = position.pixels;
    final viewportBottom = position.pixels + position.viewportDimension;
    if (y >= viewportTop + edgeMargin && y <= viewportBottom - edgeMargin) {
      return;
    }

    final target = (y - position.viewportDimension / 2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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

  /// Whether choosing "Open Link" from the selection toolbar shows an
  /// "Open link?" confirmation before launching it. Defaults to `true`.
  /// Has no effect if the controller has its own custom `onTapLink`.
  final bool confirmBeforeOpeningLinks;

  /// Horizontal alignment applied to the whole document. Defaults to
  /// [TextAlign.start]. This is a single, document-wide setting — the
  /// underlying `TextField` has no way to align individual paragraphs
  /// differently, so this cannot vary per-paragraph.
  final TextAlign textAlign;

  /// Base text direction for the whole document. Left `null` (the
  /// default), the editor inherits the ambient [Directionality] from its
  /// context, same as any other Flutter text widget. Like [textAlign],
  /// this applies to the whole document, not per-paragraph.
  final TextDirection? textDirection;

  /// Overrides the selection toolbar entirely.
  ///
  /// Left `null` (the default), the editor shows its own built-in
  /// toolbar: the platform-native `AdaptiveTextSelectionToolbar`, with
  /// Copy/Cut/Paste redirected through this editor's rich-clipboard-
  /// preserving `RichEditorController`, plus Open/Edit/Remove buttons
  /// whenever the selection sits entirely inside a link.
  ///
  /// Supplying a builder here replaces all of that, including the
  /// link-aware buttons. For lighter customization — matching your app's
  /// color scheme without giving up the built-in link-awareness — prefer
  /// wrapping this widget in `Theme`/`CupertinoTheme` instead.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  const RichTextEditor({
    super.key,
    required this.controller,
    required this.scrollController,
    this.showMargin = true,
    this.lineStyle = RuledLineStyle.solid,
    this.editorStyle = RichEditorStyle.standard,
    this.onToggleFind,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.confirmBeforeOpeningLinks = true,
    this.contextMenuBuilder,
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

  // The selection toolbar's full native button set — Copy/Cut/Paste,
  // Select All, and (where supported) Look Up/Search Web/Share/Live Text
  // — with only Copy/Cut/Paste's `onPressed` swapped to go through
  // `controller`'s rich clipboard path instead of the plain-text default.
  List<ContextMenuButtonItem> _richButtonItems(
    EditableTextState editableTextState,
  ) {
    return [
      for (final item in editableTextState.contextMenuButtonItems)
        switch (item.type) {
          ContextMenuButtonType.copy => item.copyWith(
            onPressed: () {
              controller.copy();
              editableTextState.hideToolbar();
            },
          ),
          ContextMenuButtonType.cut => item.copyWith(
            onPressed: () {
              controller.cut();
              editableTextState.hideToolbar();
            },
          ),
          ContextMenuButtonType.paste => item.copyWith(
            onPressed: () {
              controller.paste();
              editableTextState.hideToolbar();
            },
          ),
          _ => item,
        },
    ];
  }

  // The selection toolbar shown unless a host supplies its own
  // contextMenuBuilder — the native button set plus Open/Edit/Remove
  // when the selection sits entirely inside a single link (not merely
  // touching one at its start offset, which could span far beyond it).
  Widget _defaultContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final selection = editableTextState.textEditingValue.selection;
    if (!selection.isValid) {
      return const SizedBox.shrink();
    }

    final linkRange = controller.linkRangeAt(selection.start);
    final linkUrl = controller.linkUrlAt(selection.start);
    final selectionIsWithinLink =
        linkUrl != null &&
        linkRange != null &&
        selection.start >= linkRange.start &&
        selection.end <= linkRange.end;

    if (!selectionIsWithinLink) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: _richButtonItems(editableTextState),
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
            controller.selection = TextSelection(
              baseOffset: linkRange.start,
              extentOffset: linkRange.end,
            );
            final url = await showLinkEntryDialog(
              context,
              initialUrl: linkUrl,
            );
            if (url != null) {
              controller.setLink(url);
            }
          },
        ),
        ContextMenuButtonItem(
          label: 'Remove',
          onPressed: () {
            editableTextState.hideToolbar();
            controller.selection = TextSelection(
              baseOffset: linkRange.start,
              extentOffset: linkRange.end,
            );
            controller.setLink(null);
          },
        ),
        ..._richButtonItems(editableTextState),
      ],
    );
  }

  // Makes a list marker act like a single unit for plain Left/Right
  // caret movement, so it can't be landed on one character in. Pure
  // cursor positioning, no text mutation. Shift/Ctrl/Cmd/Alt+Arrow keep
  // Flutter's normal behavior untouched.
  KeyEventResult _handleSmartArrowKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final isRight = event.logicalKey == LogicalKeyboardKey.arrowRight;
    if (!isLeft && !isRight) return KeyEventResult.ignored;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final hasModifier =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    if (hasModifier) return KeyEventResult.ignored;

    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

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
      controller.selection = TextSelection.collapsed(
        offset: record.start + prefixLen,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Read once, outside any controller-listening scope: wrapping this
    // whole subtree in a ListenableBuilder on `controller` forces the
    // ruled-lines/margin painting to rebuild on every selection-drag
    // pointer-move, fighting RenderEditable's own gesture tracking.
    final renderTheme = controller.renderer.theme;
    final resolvedTextDirection = textDirection ?? Directionality.of(context);

    final baseTextStyle = TextStyle(
      fontSize: renderTheme.baseFontSize,
      height: renderTheme.lineHeight / renderTheme.baseFontSize,
      color: Colors.black,
      letterSpacing: 0.2,
    );
    final strutStyle = StrutStyle(
      fontSize: renderTheme.baseFontSize,
      height: renderTheme.lineHeight / renderTheme.baseFontSize,
      // forceStrutHeight defaults to false: a header's line height is
      // already quantized up to a multiple of renderTheme.lineHeight, so
      // the strut only sets a floor for plain body text.
      leading: 0.0,
    );

    // Assigned directly (not chained onto whatever was there before) —
    // this widget is stateless and build() can run many times, so
    // capturing "the previous handler" each time would nest an
    // unbounded nested-handler chain across rebuilds.
    controller.focusNode.onKeyEvent = _handleSmartArrowKeys;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            const ToggleBoldIntent(),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            const ToggleBoldIntent(),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true):
            const ToggleItalicIntent(),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            const ToggleItalicIntent(),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true):
            const ToggleUnderlineIntent(),
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true):
            const ToggleUnderlineIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const ToggleFindIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            const ToggleFindIntent(),
        const SingleActivator(LogicalKeyboardKey.tab): const IndentListIntent(),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true):
            const OutdentListIntent(),
        const SingleActivator(
          LogicalKeyboardKey.digit8,
          control: true,
          shift: true,
        ): const ToggleBulletListIntent(),
        const SingleActivator(
          LogicalKeyboardKey.digit8,
          meta: true,
          shift: true,
        ): const ToggleBulletListIntent(),
        const SingleActivator(
          LogicalKeyboardKey.digit7,
          control: true,
          shift: true,
        ): const ToggleNumberedListIntent(),
        const SingleActivator(
          LogicalKeyboardKey.digit7,
          meta: true,
          shift: true,
        ): const ToggleNumberedListIntent(),
        const SingleActivator(
          LogicalKeyboardKey.digit9,
          control: true,
          shift: true,
        ): const ToggleTaskItemIntent(),
        const SingleActivator(
          LogicalKeyboardKey.digit9,
          meta: true,
          shift: true,
        ): const ToggleTaskItemIntent(),
        const SingleActivator(
          LogicalKeyboardKey.digit1,
          control: true,
          alt: true,
        ): const SetHeaderIntent(
          'h1',
        ),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true, alt: true):
            const SetHeaderIntent('h1'),
        const SingleActivator(
          LogicalKeyboardKey.digit2,
          control: true,
          alt: true,
        ): const SetHeaderIntent(
          'h2',
        ),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true, alt: true):
            const SetHeaderIntent('h2'),
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
          ToggleTaskItemIntent: CallbackAction<ToggleTaskItemIntent>(
            onInvoke: (intent) {
              controller.toggleTaskItem();
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
          // Overrides the intent (not the key binding) so Flutter's own
          // default Ctrl/Cmd+Z shortcut drives our HistoryManager instead
          // of TextField's internal undo, which would desync formatting.
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            // Single, shared left-padding animation — the ruled-lines
            // width calc and the real TextField's own padding both read
            // this same value, rather than two animations that could
            // drift out of sync with each other.
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(
                end: showMargin
                    ? editorStyle.paddingLeftMarginOn
                    : editorStyle.paddingLeftMarginOff,
              ),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              builder: (context, leftPad, _) {
                final maxTextWidth = math.max(
                  0.0,
                  totalWidth - leftPad - editorStyle.paddingRight,
                );
                return Stack(
                  children: [
                    // Positioned.fill, not a bare child: every other
                    // child here is Positioned, so a single non-
                    // positioned child would make the Stack also size
                    // itself to fit it — collapsing the whole editor to
                    // 0x0 when this renders nothing, under loose
                    // constraints (reproduced in a real browser).
                    Positioned.fill(
                      child: _ScrollToCurrentMatch(
                        controller: controller,
                        scrollController: scrollController,
                        maxWidth: maxTextWidth,
                        style: baseTextStyle,
                        strutStyle: strutStyle,
                        topPadding: editorStyle.paddingTop,
                        textDirection: resolvedTextDirection,
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: showMargin ? 1.0 : 0.0),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOut,
                          builder: (context, marginOpacity, child) {
                            return ListenableBuilder(
                              listenable: controller,
                              builder: (context, child) {
                                final lineBottoms = controller.renderer
                                    .lineBottomOffsets(
                                      controller.document,
                                      maxWidth: maxTextWidth,
                                      style: baseTextStyle,
                                      strutStyle: strutStyle,
                                      textHeightBehavior: _kTextHeightBehavior,
                                      textDirection: resolvedTextDirection,
                                    );
                                return ListenableBuilder(
                                  listenable: scrollController,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      painter: RuledLinesPainter(
                                        lineBottoms: lineBottoms,
                                        fallbackLineHeight:
                                            renderTheme.lineHeight,
                                        topPadding: editorStyle.paddingTop,
                                        scrollOffset:
                                            scrollController.hasClients
                                            ? scrollController.offset
                                            : 0.0,
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
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: editorStyle.paddingTop,
                            left: leftPad,
                            right: editorStyle.paddingRight,
                            bottom: editorStyle.paddingBottom,
                          ),
                          // TextField has no textHeightBehavior of its
                          // own — this ambient value is the only way to
                          // reach it, and must stay in sync with the one
                          // passed to lineBottomOffsets above.
                          child: DefaultTextHeightBehavior(
                            textHeightBehavior: _kTextHeightBehavior,
                            child: TextField(
                              controller: controller,
                              focusNode: controller.focusNode,
                              scrollController: scrollController,
                              maxLines: null,
                              autofocus: true,
                              textAlign: textAlign,
                              textDirection: textDirection,
                              textCapitalization: TextCapitalization.sentences,
                              keyboardType: TextInputType.multiline,
                              selectionHeightStyle: BoxHeightStyle.tight,
                              selectionWidthStyle: BoxWidthStyle.tight,
                              style: baseTextStyle,
                              strutStyle: strutStyle,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              contextMenuBuilder:
                                  contextMenuBuilder ??
                                  _defaultContextMenuBuilder,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: ListenableBuilder(
                        listenable: controller,
                        builder: (context, child) {
                          final sel = controller.selection;
                          final url = sel.isValid && sel.isCollapsed
                              ? controller.linkUrlAt(sel.start)
                              : null;
                          if (url == null) return const SizedBox.shrink();
                          return LinkPreviewBar(
                            url: url,
                            onOpen: () => _openLink(context, url),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
