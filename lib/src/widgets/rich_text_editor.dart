import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/rendering.dart' show RenderEditable;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clipboard/native/rich_clipboard_platform.dart';
import '../controller/image_actions.dart';
import '../controller/rich_editor_controller.dart';
import '../models/image_block.dart';
import '../painters/ruled_lines_painter.dart';
import '../rendering/code_block_region.dart';
import '../rendering/image_region.dart';
import '../rendering/editor_style.dart';
import '../search/search_index.dart';
import '../utils/link_launcher.dart';
import '../utils/list_prefix.dart';
import 'link_edit_sheet.dart';
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
      controller.isCodeBlockActive ||
      controller.isListActive(ParagraphListType.bullet) ||
      controller.isListActive(ParagraphListType.numbered);

  @override
  Object? invoke(IndentListIntent intent) {
    // In code Tab is an indent, not a list operation (and never moves focus).
    controller.isCodeBlockActive ? controller.indentCode() : controller.indentList();
    return null;
  }
}

class _OutdentListAction extends Action<OutdentListIntent> {
  _OutdentListAction(this.controller);
  final RichEditorController controller;

  @override
  bool get isActionEnabled =>
      controller.isCodeBlockActive ||
      controller.isListActive(ParagraphListType.bullet) ||
      controller.isListActive(ParagraphListType.numbered);

  @override
  Object? invoke(OutdentListIntent intent) {
    controller.isCodeBlockActive ? controller.outdentCode() : controller.outdentList();
    return null;
  }
}

// `RenderEditable` reserves `1.0 + cursorWidth` pixels of each line for the
// caret (`_kCaretGap` is private to the framework, hence the mirror here).
// The field's `cursorWidth` is set explicitly from [_kCursorWidth] so the two
// can not drift apart.
const _kCaretGap = 1.0;
const _kCursorWidth = 2.0;

// Shared by the real `TextField` (via `DefaultTextHeightBehavior`) and
// `TextSpanRenderer.lineBottomOffsets`'s parallel layout — both must use
// the same value or they'll disagree about where a line's glyphs fall.
//
// `proportional` (not `even`): the spare leading in a row goes above the
// glyphs, so the baseline keeps one constant distance from its ruled line
// at every font size and row count. Measured with real Roboto metrics, `even`
// drifts the baseline by several px across sizes and floats multi-row
// headings mid-row.
const _kTextHeightBehavior = TextHeightBehavior(
  leadingDistribution: TextLeadingDistribution.proportional,
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
    required this.textScaler,
    required this.devicePixelRatio,
  });

  final RichEditorController controller;
  final ScrollController scrollController;
  final double maxWidth;
  final TextStyle style;
  final StrutStyle strutStyle;
  final double topPadding;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final double devicePixelRatio;

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
          textScaler: widget.textScaler,
          devicePixelRatio: widget.devicePixelRatio,
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

  /// Forwarded verbatim to the underlying `TextField` — e.g. a
  /// `LengthLimitingTextInputFormatter` to cap note length at the input
  /// layer, the same way any other Flutter text field would. Applied
  /// before text ever reaches [controller]/the document.
  final List<TextInputFormatter>? inputFormatters;

  /// Whether the editor requests keyboard focus as soon as it's built.
  /// Defaults to `true`, matching plain Flutter `TextField`/`TextFormField`
  /// convention... except `TextField.autofocus` itself actually defaults
  /// to `false`; `true` is kept here only for backward compatibility with
  /// hosts built before this parameter existed. Prefer passing `false`
  /// explicitly for any editor that isn't the sole focus target on
  /// first frame (e.g. one embedded in a page with its own title field,
  /// or reached via a transition where grabbing the keyboard immediately
  /// would fight the transition/hero animation).
  final bool autofocus;

  /// Hint text shown when the document is empty. `null` (the default)
  /// shows no hint, matching plain `TextField` behavior.
  final String? placeholder;

  /// Whether a plain tap on a link opens it (through the controller's
  /// `onTapLink` if it has one, otherwise the "Open link?" confirmation and
  /// the platform launcher), in addition to placing the caret there.
  ///
  /// Off by default: a tap in editable text is also how the caret is moved.
  /// It is detected from raw pointer events rather than span gesture
  /// recognizers, which Flutter does not support inside an editable field.
  final bool openLinksOnTap;

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
    this.inputFormatters,
    this.autofocus = true,
    this.placeholder,
    this.openLinksOnTap = false,
  });

  // The bar's Open is an explicit action: it opens at once, with no "Open link?"
  // prompt in between (the prompt guards an accidental tap on the text).
  void _openLinkNow(BuildContext context, String url) {
    if (controller.hasCustomTapHandler) {
      controller.renderer.onTapLink?.call(url);
    } else {
      openLinkNow(context, url);
    }
  }

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
      // Android offers Paste only for a text clipboard; a copied picture gets its
      // own item (found with a cheap native check, no bytes read).
      if (controller.imageStore != null) {
        return FutureBuilder<bool>(
          future: RichClipboardPlatform.hasImage(),
          builder: (context, snapshot) => AdaptiveTextSelectionToolbar.buttonItems(
            anchors: editableTextState.contextMenuAnchors,
            buttonItems: [
              ..._richButtonItems(editableTextState),
              if (snapshot.data == true)
                ContextMenuButtonItem(
                  label: 'Paste image',
                  onPressed: () {
                    editableTextState.hideToolbar();
                    controller.pasteImageFromClipboard(force: true);
                  },
                ),
              if (!selection.isCollapsed)
                ContextMenuButtonItem(
                  label: 'Link',
                  onPressed: () {
                    editableTextState.hideToolbar();
                    showLinkSheetFor(context, controller);
                  },
                ),
            ],
          ),
        );
      }
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: [
          ..._richButtonItems(editableTextState),
          if (!selection.isCollapsed)
            ContextMenuButtonItem(
              label: 'Link',
              onPressed: () {
                editableTextState.hideToolbar();
                showLinkSheetFor(context, controller);
              },
            ),
        ],
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
    // Must reach every manual measurement below (`lineBottomOffsets`,
    // `offsetYFor`, and the header/oversized-run clamp inside the
    // renderer) so they agree with what the real `TextField` renders --
    // that field has no explicit `textScaler` override, so it applies
    // this exact ambient value automatically.
    final textScaler = MediaQuery.textScalerOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    // The style `TextField` merges its own onto (Material input text style),
    // which is where a themed font family comes from. Every manual
    // measurement below must use the same merged style, or a themed font
    // would wrap differently in the measurement than in the real field and
    // the ruled lines would stop matching the text.
    final theme = Theme.of(context);
    final inputTextStyle =
        (theme.useMaterial3 ? theme.textTheme.bodyLarge : theme.textTheme.titleMedium) ??
        const TextStyle();
    // The one row grid (scaled, pixel-snapped pitch) shared with the
    // renderer's span heights and the painter below — same scaler, same
    // ratio, same instance-per-inputs, so none of them can disagree.
    final metrics = controller.renderer.rowMetrics(
      textScaler: textScaler,
      devicePixelRatio: devicePixelRatio,
      style: inputTextStyle,
    );
    final rowHeight = metrics.heightMultiplier(renderTheme.baseFontSize);

    final baseTextStyle = TextStyle(
      fontSize: renderTheme.baseFontSize,
      height: rowHeight,
      leadingDistribution: TextLeadingDistribution.proportional,
      color: renderTheme.textColor,
      letterSpacing: 0.2,
    );
    final measuredStyle = inputTextStyle.merge(baseTextStyle);
    // A forced strut takes its baseline from the strut's own font, so it must
    // resolve to the same family the field's text does or the baseline would
    // sit at the wrong height within the row.
    final strutStyle = StrutStyle(
      fontFamily: measuredStyle.fontFamily,
      fontFamilyFallback: measuredStyle.fontFamilyFallback,
      fontSize: renderTheme.baseFontSize,
      height: rowHeight,
      leadingDistribution: TextLeadingDistribution.proportional,
      // When every header fits one row (the Notebook policy) the strut is
      // forced, so no line can be anything but exactly one pitch — including
      // a line that mixes fallback fonts (CJK, emoji), whose per-font
      // ascent/descent split otherwise makes it a pixel taller. If a header
      // needs several rows it must be allowed to exceed the strut, so the
      // force is off and the strut is only the floor for an empty line.
      forceStrutHeight: metrics.allHeadersFitOneRow,
      leading: 0.0,
    );

    // The one measurement of the document's lines (cached by the renderer):
    // the ruled-lines painter and the code-block actions both read from it.
    List<double> layoutBottoms(double maxTextWidth) =>
        controller.renderer.lineBottomOffsets(
          controller.document,
          maxWidth: maxTextWidth,
          style: measuredStyle,
          strutStyle: strutStyle,
          textHeightBehavior: _kTextHeightBehavior,
          textDirection: resolvedTextDirection,
          textScaler: textScaler,
          devicePixelRatio: devicePixelRatio,
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
                // The width the real field wraps at: `RenderEditable` lays text
                // out `_kCaretGap + cursorWidth` narrower than its box to keep
                // room for the caret. Measuring at the full box width would let
                // a line that fits in that last few pixels stay on one row here
                // while the field wraps it, shifting every rule below it.
                final maxTextWidth = math.max(
                  0.0,
                  totalWidth -
                      leftPad -
                      editorStyle.paddingRight -
                      _kCaretGap -
                      _kCursorWidth,
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
                        style: measuredStyle,
                        strutStyle: strutStyle,
                        topPadding: editorStyle.paddingTop,
                        textDirection: resolvedTextDirection,
                        textScaler: textScaler,
                        devicePixelRatio: devicePixelRatio,
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
                              // Only recalculate line geometry when the document
                              // itself changes, not on every selection move.
                              listenable: controller.documentMutationNotifier,
                              builder: (context, child) {
                                final lineBottoms = layoutBottoms(maxTextWidth);
                                return ListenableBuilder(
                                  // Scrolling, and — for the selected-blank-line
                                  // bars only — selection/focus changes. The paper
                                  // layer is its own repaint boundary, so a drag
                                  // repaints just a few rules here.
                                  listenable: Listenable.merge([
                                    scrollController,
                                    controller,
                                    controller.focusNode,
                                    if (controller.imageCache != null) controller.imageCache!,
                                  ]),
                                  builder: (context, child) {
                                    final sel = controller.selection;
                                    final imageBlocks = controller.renderer.imageBlocks;
                                    final imageCache = controller.imageCache;
                                    if (imageCache != null && imageBlocks.isNotEmpty) {
                                      // Ask only for pictures on, or just off, the screen.
                                      final scrolled = scrollController.hasClients ? scrollController.offset : 0.0;
                                      final viewport = scrollController.hasClients ? scrollController.position.viewportDimension : 900.0;
                                      final wanted = ((totalWidth - leftPad - editorStyle.paddingRight) * devicePixelRatio).round();
                                      for (final b in imageBlocks) {
                                        final top = editorStyle.paddingTop + b.top - scrolled;
                                        if (top + b.height > -400 && top < viewport + 400) imageCache.ensure(b.id, wanted);
                                      }
                                    }
                                    final selectedBlank = sel.isValid && !sel.isCollapsed && controller.focusNode.hasFocus
                                        ? controller.renderer.blankLinesSelected(sel.start, sel.end)
                                        : const <BlankLineRegion>[];
                                    return CustomPaint(
                                      painter: RuledLinesPainter(
                                        selectedBlankLines: selectedBlank,
                                        selectionColor:
                                            DefaultSelectionStyle.of(context).selectionColor ??
                                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                        selectionBarLeft: leftPad,
                                        selectionBarWidth: 10,
                                        lineBottoms: lineBottoms,
                                        codeBlocks: controller.renderer.codeBlocks,
                                        imageBlocks: imageBlocks,
                                        imageCache: imageCache,
                                        imageLeft: leftPad,
                                        imageRight: totalWidth - editorStyle.paddingRight,
                                        selectionStart: controller.focusNode.hasFocus && sel.isValid ? sel.start : -1,
                                        selectionEnd: controller.focusNode.hasFocus && sel.isValid ? sel.end : -1,
                                        imageAccent: Theme.of(context).colorScheme.primary,
                                        codeBlockColor: editorStyle.codeBlockColor,
                                        codeBorderColor: editorStyle.codeBlockLabelColor.withValues(alpha: 0.22),
                                        inlineCode: controller.renderer.inlineCodeRects,
                                        inlineCodeLeft: leftPad,
                                        inlineCodeColor: editorStyle.codeBlockColor,
                                        codeLeft: leftPad - 8,
                                        codeRight: totalWidth - editorStyle.paddingRight + 8,
                                        fallbackLineHeight: metrics.pitch,
                                        devicePixelRatio: devicePixelRatio,
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
                        child: _LinkTapListener(
                          enabled: openLinksOnTap,
                          controller: controller,
                          onOpen: (url) => _openLink(context, url),
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
                          // The field's scroll area ends [paddingBottom] above the
                          // editor's bottom edge (that gap is the end-of-note breathing
                          // room). Its clip is widened by the same amount so a line
                          // scrolling through that gap is drawn whole instead of being
                          // cut mid-glyph at an invisible edge above the bottom bar.
                          child: ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) => ClipRect(
                            clipper: _ExtendBottomClipper(editorStyle.paddingBottom),
                            child: DefaultTextHeightBehavior(
                            textHeightBehavior: _kTextHeightBehavior,
                            child: TextField(
                              clipBehavior: Clip.none,
                              // A picture is selected as a whole: no caret on its blank rows.
                              showCursor: controller.selectedImageRun == null ? null : false,
                              contentInsertionConfiguration: controller.imageStore == null
                                  ? null
                                  : ContentInsertionConfiguration(
                                      allowedMimeTypes: const ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
                                      onContentInserted: (content) {
                                        final bytes = content.data;
                                        if (bytes != null) controller.insertImageBytes(bytes);
                                      },
                                    ),
                              controller: controller,
                              focusNode: controller.focusNode,
                              scrollController: scrollController,
                              maxLines: null,
                              cursorWidth: _kCursorWidth,
                              autofocus: autofocus,
                              textAlign: textAlign,
                              textDirection: textDirection,
                              textCapitalization: TextCapitalization.sentences,
                              keyboardType: TextInputType.multiline,
                              // Whole-row height: `max` boxes span the full ruled row, not
                              // just the glyph band, so a multi-line selection is one
                              // continuous band on the paper with no unselected sliver
                              // between rows. Width stays `tight` — it follows the
                              // selected text (spaces included) exactly. (`max` width was
                              // tried on a device: selecting the last word of a line
                              // painted the whole rest of the row, which reads as a bigger
                              // selection than was made.)
                              selectionHeightStyle: BoxHeightStyle.max,
                              selectionWidthStyle: BoxWidthStyle.tight,
                              style: baseTextStyle,
                              strutStyle: strutStyle,
                              inputFormatters: inputFormatters,
                              decoration: InputDecoration(
                                // Explicit `false`/`none`/zero on every
                                // fill-affecting property, not just the
                                // ones this editor wants — a host's ambient
                                // `Theme.inputDecorationTheme` (e.g.
                                // `filled: true` with a rounded
                                // `OutlineInputBorder`, common in Material
                                // 3 apps) would otherwise paint straight
                                // through any gaps left unset, showing up
                                // as an unwanted rounded card behind the
                                // ruled paper.
                                filled: false,
                                fillColor: Colors.transparent,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintText: placeholder,
                                hintStyle: baseTextStyle.copyWith(
                                  color: baseTextStyle.color?.withValues(alpha: 0.4),
                                ),
                              ),
                              contextMenuBuilder:
                                  contextMenuBuilder ??
                                  _defaultContextMenuBuilder,
                            ),
                          ),
                          ),
                          ),
                        ),
                        ),
                      ),
                    ),
                    // Copy / language actions of each visible code block. Only the
                    // buttons themselves take pointer events; the rest of this
                    // layer lets taps through to the text field.
                    Positioned.fill(
                      child: _CodeBlockActions(
                        controller: controller,
                        scrollController: scrollController,
                        style: editorStyle,
                        rightInset: editorStyle.paddingRight,
                        textLeft: leftPad,
                        // Same call (same cache key) as the painter's, so the
                        // regions are current even if this layer rebuilds
                        // before the painter's does.
                        regions: () {
                          layoutBottoms(maxTextWidth);
                          return controller.renderer.codeBlocks;
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: _ImageActions(
                        controller: controller,
                        scrollController: scrollController,
                        style: editorStyle,
                        leftInset: leftPad,
                        rightInset: editorStyle.paddingRight,
                        // Same call (same cache key) as the painter's, so the block is
                        // where the layout now says, not where it was a frame ago.
                        regions: () {
                          layoutBottoms(maxTextWidth);
                          return controller.renderer.imageBlocks;
                        },
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: _LinkBarHost(
                        controller: controller,
                        scrollController: scrollController,
                        onOpen: (url) => _openLinkNow(context, url),
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

/// The chip's text: the block's label; for an unlabelled block the language its
/// text looks like (what its colours follow); "plain text" for an explicit
/// plain block; "code" when there is nothing to say.
String _chipLabel(CodeBlockRegion block) {
  final language = block.language;
  if (language == 'text') return 'plain text';
  return language ?? block.guessedLanguage ?? 'code';
}

/// Controls of the selected picture: smaller, larger and remove, floating at its
/// top-right corner. Only the one selected picture has them, so a note full of
/// pictures builds nothing extra.
class _ImageActions extends StatelessWidget {
  const _ImageActions({
    required this.controller,
    required this.scrollController,
    required this.style,
    required this.leftInset,
    required this.rightInset,
    required this.regions,
  });

  final RichEditorController controller;
  final ScrollController scrollController;
  final RichEditorStyle style;
  final double leftInset;
  final double rightInset;
  final List<ImageRegion> Function() regions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, scrollController, if (controller.imageCache != null) controller.imageCache!]),
      builder: (context, _) {
        final run = controller.selectedImageRun;
        if (run == null) return const SizedBox.shrink();
        ImageRegion? region;
        for (final b in regions()) {
          if (b.level == run.level) {
            region = b;
            break;
          }
        }
        if (region == null) return const SizedBox.shrink();
        final scroll = scrollController.hasClients ? scrollController.offset : 0.0;
        final top = style.paddingTop + region.top - scroll + RuledLinesPainter.imageInset;
        return LayoutBuilder(
          builder: (context, constraints) {
            if (top + 40 < style.paddingTop || top > constraints.maxHeight) return const SizedBox.shrink();
            // Against the picture's own right edge, not the text area's.
            final area = Rect.fromLTRB(leftInset, 0, constraints.maxWidth - rightInset, 100);
            final image = controller.imageCache?.peek(region!.id);
            final pitch = region!.height / run.rows;
            final innerHeight = region.height - 2 * RuledLinesPainter.imageInset;
            final drawn = image == null
                ? null
                : RuledLinesPainter.imageDestination(
                    Rect.fromLTRB(area.left, 0, area.right, innerHeight),
                    Size(image.width.toDouble(), image.height.toDouble()),
                  );
            final right = drawn?.right ?? area.right;

            // Smaller / Larger move the picture one row at a time. Larger stops where
            // the picture is as wide as the text (more rows would only add empty
            // room under it); Smaller, from there, first drops that spare room and
            // then shrinks the picture. Each tap is a visible change.
            VoidCallback? stepTo(int direction) {
              final int target;
              if (image == null || drawn == null) {
                target = run.rows + direction;
              } else {
                final fullWidth = drawn.width >= area.width * 0.985;
                final needed = ((area.width * image.height / image.width + 2 * RuledLinesPainter.imageInset) / pitch).ceil();
                if (direction > 0) {
                  if (fullWidth) return null;
                  target = run.rows + 1;
                } else {
                  target = fullWidth ? math.min(run.rows - 1, needed - 1) : run.rows - 1;
                }
              }
              if (target < minImageRows || target > maxImageRows || target == run.rows) {
                return direction < 0 && run.rows > minImageRows && target < minImageRows
                    ? () => controller.resizeImage(controller.selectedImageRun ?? run, minImageRows - (controller.selectedImageRun ?? run).rows)
                    : null;
              }
              return () {
                final current = controller.selectedImageRun ?? run;
                controller.resizeImage(current, target - current.rows);
              };
            }

            // The controls sit in the picture's top-right corner; on a small picture
            // (they would cover most of it, or hang off its left edge) they go
            // beside it instead, in the free room to its right.
            const pillWidth = _ImageButtons.width;
            final beside = drawn != null && drawn.width < pillWidth * 2.4 && area.right - drawn.right >= pillWidth + 12;
            return Stack(
              children: [
                Positioned(
                  top: top + 8,
                  left: beside ? drawn.right + 10 : null,
                  right: beside ? null : constraints.maxWidth - right + 8,
                  child: _ImageButtons(controller: controller, onSmaller: stepTo(-1), onLarger: stepTo(1)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ImageButtons extends StatelessWidget {
  const _ImageButtons({required this.controller, required this.onSmaller, required this.onLarger});

  /// Three 36-wide buttons.
  static const double width = 108;

  final RichEditorController controller;

  /// `null` when the picture cannot go smaller / larger.
  final VoidCallback? onSmaller;
  final VoidCallback? onLarger;

  void _act(void Function(ImageRun) action) {
    final current = controller.selectedImageRun;
    if (current != null) action(current);
  }

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback? onTap) => IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: onTap == null ? Colors.white38 : Colors.white),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
    return Material(
      color: const Color(0xCC1C1B1F),
      elevation: 3,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Each acts on the picture selected *now* (a tap may land before this row
          // has rebuilt from the previous one).
          button(Icons.photo_size_select_small_rounded, 'Smaller', onSmaller),
          button(Icons.photo_size_select_large_rounded, 'Larger', onLarger),
          button(Icons.delete_outline_rounded, 'Remove picture', () => _act(controller.deleteImage)),
        ],
      ),
    );
  }
}

/// Clips to the child's box, extended downward by [extra].
class _ExtendBottomClipper extends CustomClipper<Rect> {
  const _ExtendBottomClipper(this.extra);

  final double extra;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, size.height + extra);

  @override
  bool shouldReclip(_ExtendBottomClipper old) => old.extra != extra;
}

/// Shows the link bar for a link the user has just touched: the editor must
/// have focus (a note that merely opens with its caret inside a link stays
/// quiet), the caret must be in the link, and the bar goes away when the user
/// dismisses it, scrolls, or moves the caret.
class _LinkBarHost extends StatefulWidget {
  const _LinkBarHost({required this.controller, required this.scrollController, required this.onOpen});

  final RichEditorController controller;
  final ScrollController scrollController;
  final void Function(String url) onOpen;

  @override
  State<_LinkBarHost> createState() => _LinkBarHostState();
}

class _LinkBarHostState extends State<_LinkBarHost> {
  int? _dismissedAt;
  String? _lastText;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _LinkBarHost old) {
    super.didUpdateWidget(old);
    if (old.scrollController != widget.scrollController) {
      old.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  // Scrolling away is a "not now": hide until the caret moves.
  void _onScroll() {
    final sel = widget.controller.selection;
    if (_dismissedAt == null && sel.isValid && sel.isCollapsed && widget.controller.linkUrlAt(sel.start) != null) {
      setState(() => _dismissedAt = sel.start);
    }
  }

  Future<void> _edit(BuildContext context, int offset) => showLinkSheetFor(context, widget.controller);

  void _remove(int offset) {
    final c = widget.controller;
    final range = c.linkRangeAt(offset);
    if (range == null) return;
    c.editLink(range, c.document.text.substring(range.start, range.end), null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.controller.focusNode]),
      builder: (context, _) {
        final c = widget.controller;
        final sel = c.selection;
        final url = c.focusNode.hasFocus && sel.isValid && sel.isCollapsed ? c.linkUrlAt(sel.start) : null;
        // Typing or pasting leaves the caret in or beside a link without the
        // user having touched it: stay quiet until the caret moves on.
        final text = c.value.text;
        final edited = _lastText != null && !identical(_lastText, text) && _lastText != text;
        _lastText = text;
        if (url == null) {
          _dismissedAt = null;
          return const SizedBox.shrink();
        }
        if (edited) _dismissedAt = sel.start;
        if (_dismissedAt == sel.start) return const SizedBox.shrink();
        _dismissedAt = null;
        return LinkPreviewBar(
          url: url,
          onOpen: () => widget.onOpen(url),
          onEdit: () => _edit(context, sel.start),
          onRemove: () => _remove(sel.start),
        );
      },
    );
  }
}

/// A small "language · copy" chip on the top-right edge of every code block
/// currently in view. Positions come from the same cached layout the ruled
/// lines use (`TextSpanRenderer.codeBlocks`), re-read on every document change
/// or scroll, so no extra text layout happens here.
class _CodeBlockActions extends StatelessWidget {
  const _CodeBlockActions({
    required this.controller,
    required this.scrollController,
    required this.style,
    required this.rightInset,
    required this.textLeft,
    required this.regions,
  });

  final RichEditorController controller;
  final ScrollController scrollController;
  final RichEditorStyle style;
  final double rightInset;
  final double textLeft;
  final List<CodeBlockRegion> Function() regions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller.documentMutationNotifier, scrollController]),
      builder: (context, _) {
        final blocks = regions();
        if (blocks.isEmpty) return const SizedBox.shrink();
        final scroll = scrollController.hasClients ? scrollController.offset : 0.0;
        // The height of this editor's own area. (Not the scroll position's
        // viewport: the field grows with its content, and that dimension lags a
        // frame behind a paste or an import, which would hide a new block's chip.)
        return LayoutBuilder(
          builder: (context, constraints) {
            final children = <Widget>[];
            for (final block in blocks) {
              final top = style.paddingTop + block.top - scroll;
              // Hidden once the block's top edge has scrolled under the text
              // area's top (the header above the editor is not part of it).
              if (top < style.paddingTop - 1 || top > constraints.maxHeight) continue;
              // The chip lives inside the card, never over code. By what is
              // actually there: on the first row when its text stops short of the
              // chip; else on the last row (of a multi-row block); else, when both
              // rows run long, a compact chip in the card's top padding strip,
              // above the glyphs.
              final label = _chipLabel(block);
              final chipWidth = 36 + label.length * 6.6;
              final chipLeft = constraints.maxWidth - (rightInset - 6) - chipWidth - 6;
              const chipHeight = 24.0;
              final cardTop = top + RuledLinesPainter.codeBlockInsetTop;
              final multiRow = block.lastRowTop > block.top + 0.5;
              final firstClear = textLeft + block.firstLineRight < chipLeft;
              final lastClear = multiRow && textLeft + block.lastLineRight < chipLeft;
              final double chipTop;
              var compact = false;
              if (firstClear) {
                chipTop = cardTop + (block.firstRowBottom - block.top - RuledLinesPainter.codeBlockInsetTop - chipHeight) / 2 + 2;
              } else if (lastClear) {
                final rowTop = style.paddingTop + block.lastRowTop - scroll;
                chipTop = rowTop + (block.bottom - block.lastRowTop - chipHeight) / 2 + 2;
              } else {
                compact = true;
                chipTop = cardTop;
              }
              children.add(
                Positioned(
                  top: chipTop,
                  right: rightInset - 6,
                  child: _CodeBlockChip(controller: controller, block: block, color: style.codeBlockLabelColor, compact: compact),
                ),
              );
            }
            return Stack(children: children);
          },
        );
      },
    );
  }
}

class _CodeBlockChip extends StatelessWidget {
  const _CodeBlockChip({required this.controller, required this.block, required this.color, this.compact = false});

  /// A smaller chip that fits in the card's top padding strip.
  final bool compact;

  final RichEditorController controller;
  final CodeBlockRegion block;
  final Color color;

  Future<void> _editLanguage(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _CodeLanguageDialog(initial: block.language == 'text' ? '' : (block.language ?? '')),
    );
    if (result == null) return;
    controller.selection = TextSelection.collapsed(offset: block.start);
    controller.setCodeBlockLanguage(result);
  }

  @override
  Widget build(BuildContext context) {
    final label = _chipLabel(block);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _editLanguage(context),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 0 : 2),
            child: Text(label, style: TextStyle(fontSize: compact ? 10 : 11, height: compact ? 1.2 : null, color: color, fontWeight: FontWeight.w600)),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            controller.copyRange(block.start, block.end);
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 1)),
            );
          },
          child: Padding(
            padding: EdgeInsets.all(compact ? 1 : 4),
            child: Icon(Icons.copy_rounded, size: compact ? 12 : 15, color: color),
          ),
        ),
      ],
    );
  }
}

// Owns its TextEditingController, so it is disposed only once the dialog's
// exit animation has finished with it.
class _CodeLanguageDialog extends StatefulWidget {
  const _CodeLanguageDialog({required this.initial});

  final String initial;

  @override
  State<_CodeLanguageDialog> createState() => _CodeLanguageDialogState();
}

// Offered as one-tap choices; anything else can be typed.
const _commonLanguages = <(String, String)>[
  ('Dart', 'dart'),
  ('JavaScript', 'javascript'),
  ('TypeScript', 'typescript'),
  ('Python', 'python'),
  ('Java', 'java'),
  ('Kotlin', 'kotlin'),
  ('Swift', 'swift'),
  ('C', 'c'),
  ('C++', 'cpp'),
  ('C#', 'csharp'),
  ('Go', 'go'),
  ('Rust', 'rust'),
  ('HTML', 'html'),
  ('CSS', 'css'),
  ('JSON', 'json'),
  ('YAML', 'yaml'),
  ('SQL', 'sql'),
  ('Shell', 'shell'),
  ('Markdown', 'markdown'),
];

class _CodeLanguageDialogState extends State<_CodeLanguageDialog> {
  late final TextEditingController _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Code language'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _field,
              decoration: const InputDecoration(hintText: 'e.g. dart (leave empty for none)'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                ActionChip(label: const Text('Auto-detect'), onPressed: () => Navigator.pop(context, '')),
                ActionChip(label: const Text('Plain text'), onPressed: () => Navigator.pop(context, 'text')),
                for (final (label, value) in _commonLanguages)
                  ActionChip(label: Text(label), onPressed: () => Navigator.pop(context, value)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _field.text), child: const Text('Set')),
      ],
    );
  }
}


/// Opens a link on a plain tap, from raw pointer events.
///
/// Span gesture recognizers cannot be used for this: Flutter's editable text
/// asserts against recognizers in anything but a read-only field. A [Listener]
/// does not take part in the gesture arena, so the field still handles the same
/// tap (caret placement) untouched; this only watches for a quick, still
/// press-and-release, resolves it to a text position, and — if that position is
/// on a link glyph — calls [onOpen].
class _LinkTapListener extends StatefulWidget {
  const _LinkTapListener({
    required this.enabled,
    required this.controller,
    required this.onOpen,
    required this.child,
  });

  final bool enabled;
  final RichEditorController controller;
  final void Function(String url) onOpen;
  final Widget child;

  @override
  State<_LinkTapListener> createState() => _LinkTapListenerState();
}

class _LinkTapListenerState extends State<_LinkTapListener> {
  static const _maxTapDuration = Duration(milliseconds: 350);

  Offset? _downPosition;
  Timer? _expiry; // a press held longer than a tap
  bool _expired = false;
  bool _multiTouch = false;
  int _pointers = 0;

  void _down(PointerDownEvent e) {
    _pointers++;
    if (_pointers > 1) {
      _multiTouch = true;
      return;
    }
    _multiTouch = false;
    _downPosition = e.position;
    _expired = false;
    _expiry?.cancel();
    _expiry = Timer(_maxTapDuration, () => _expired = true);
  }

  void _up(PointerUpEvent e) {
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    final down = _downPosition;
    final held = _expired;
    _expiry?.cancel();
    _downPosition = null;
    if (!widget.enabled || _multiTouch || down == null || held) return;
    if ((e.position - down).distance > kTouchSlop) return;
    _openLinkAt(e.position);
  }

  void _cancel(PointerCancelEvent e) {
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    _expiry?.cancel();
    _downPosition = null;
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  RenderEditable? _findRenderEditable() {
    RenderEditable? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  void _openLinkAt(Offset global) {
    final render = _findRenderEditable();
    if (render == null || !render.hasSize) return;
    final position = render.getPositionForPoint(global);
    final offset = position.offset;
    final controller = widget.controller;
    if (offset < 0 || offset > controller.document.text.length) return;

    // getPositionForPoint snaps a tap in the empty space after a line's text
    // to that line's end; only a tap on the link's own glyphs counts.
    final range = controller.linkRangeAt(offset) ?? (offset > 0 ? controller.linkRangeAt(offset - 1) : null);
    final url = controller.linkUrlAt(offset) ?? (offset > 0 ? controller.linkUrlAt(offset - 1) : null);
    if (range == null || url == null) return;

    final local = render.globalToLocal(global);
    final inside = _pointIsOnText(render, range.start, range.end, local, offset);
    if (inside) widget.onOpen(url);
  }

  // Whether [local] falls on the glyph of a link character next to the resolved
  // text offset: between that character's caret positions on its own line, and
  // within its row.
  bool _pointIsOnText(RenderEditable render, int start, int end, Offset local, int offset) {
    for (final c in [offset - 1, offset]) {
      if (c < start || c >= end) continue;
      final a = render.getLocalRectForCaret(TextPosition(offset: c));
      final b = render.getLocalRectForCaret(TextPosition(offset: c + 1));
      final sameLine = (a.top - b.top).abs() < 1;
      final left = a.left - 1;
      final right = sameLine ? b.left + 1 : a.left + 24; // last glyph of a wrapped line
      final rowTop = a.top - 4;
      final rowBottom = a.bottom + 4;
      if (local.dx >= left && local.dx <= right && local.dy >= rowTop && local.dy <= rowBottom) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: widget.child,
    );
  }
}
