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

/// Distributes a line's extra leading (the gap between its quantized
/// box height and its glyphs' own natural ascent+descent — see
/// `TextSpanRenderer._quantizedLineHeight`) evenly above and below the
/// glyphs, rather than Flutter's default proportional-to-the-font's-own-
/// metrics split. This is what makes a header (given 2 rows of height
/// because 1 wasn't enough) actually sit *centered* in that space
/// instead of just "not clipped" — a literal reading of "text must
/// always be centered between ruled lines no matter what". Shared by
/// the real `TextField` below (via `DefaultTextHeightBehavior`, since
/// `TextField` has no `textHeightBehavior` parameter of its own) and
/// `TextSpanRenderer.lineBottomOffsets`'s parallel layout — both need
/// the same value or they could disagree about where a line's glyphs
/// actually fall within its box.
const _kTextHeightBehavior = TextHeightBehavior(
  leadingDistribution: TextLeadingDistribution.even,
);

/// Renders nothing — its only job is scrolling [scrollController] so the
/// current search match stays visible after Find/Next/Previous.
///
/// `matchHighlightRange` already paints the current match distinctly
/// (see `TextSpanRenderer`), but painting a highlight doesn't scroll
/// anything into view on its own: `RichEditorController.findNext`/
/// `findPrevious` update `controller.selection` programmatically, not
/// through any real user gesture on the field, and `EditableText`'s
/// own bring-into-view behavior only fires for selection changes that
/// originate from an actual tap/keyboard/drag on the field itself — a
/// controller-driven selection change is invisible to it. Without this,
/// a match outside the current viewport is only "found" as far as its
/// stored selection goes; the user still has to scroll and hunt for it
/// manually, which defeats half the point of Next/Previous.
///
/// A `StatefulWidget` (unlike the rest of this file) because it has to
/// remember the *previous* current match to tell "the match changed"
/// apart from "the controller notified for some unrelated reason" (a
/// keystroke elsewhere, a formatting change) — a stateless widget has
/// nowhere to keep that between notifications.
class _ScrollToCurrentMatch extends StatefulWidget {
  const _ScrollToCurrentMatch({
    required this.controller,
    required this.scrollController,
    required this.maxWidth,
    required this.style,
    required this.strutStyle,
    required this.topPadding,
  });

  final RichEditorController controller;
  final ScrollController scrollController;
  final double maxWidth;
  final TextStyle style;
  final StrutStyle strutStyle;
  final double topPadding;

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
    // SearchMatch has value equality, so this correctly no-ops both
    // when nothing search-related changed (the common case — most
    // notifications are plain typing) and when the "new" current match
    // happens to be the exact same range as before.
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
        );

    // Already comfortably on screen -- leave the scroll position alone
    // rather than re-centering on every Next/Previous, which would be
    // more disorienting than helpful once the match is already visible.
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

  /// Overrides the selection toolbar entirely — its colors, shape,
  /// button set, or swaps in a completely different widget.
  ///
  /// Left `null` (the default), the editor shows its own built-in
  /// toolbar: the platform-native `AdaptiveTextSelectionToolbar` (Look
  /// Up/Search Web/Share/Live Text Input included wherever the platform
  /// actually supports them, exactly as `TextField` would show on its
  /// own), with Copy/Cut/Paste redirected through this editor's
  /// rich-clipboard-preserving `RichEditorController` instead of
  /// `EditableTextState`'s plain-text-only default, plus Open/Edit/
  /// Remove buttons whenever the selection sits entirely inside a link.
  ///
  /// Supplying a builder here replaces all of that, including the
  /// link-aware buttons — reconstruct them yourself (via
  /// `controller.linkUrlAt`/`linkRangeAt`) if your builder still wants
  /// them. For *lighter* customization — matching your app's color
  /// scheme without giving up the built-in link-awareness — prefer
  /// wrapping this widget in `Theme`/`CupertinoTheme` instead of
  /// overriding this at all: `AdaptiveTextSelectionToolbar`'s Material
  /// buttons already read `Theme.of(context)` and its Cupertino buttons
  /// read `CupertinoTheme.of(context)`, so most "make it match my app"
  /// requests need no builder here to begin with.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  const RichTextEditor({
    super.key,
    required this.controller,
    required this.scrollController,
    this.showMargin = true,
    this.lineStyle = RuledLineStyle.solid,
    this.editorStyle = RichEditorStyle.standard,
    this.onToggleFind,
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

  /// The selection toolbar's full native button set — Copy/Cut/Paste,
  /// Select All, and (where the platform supports them) Look Up, Search
  /// Web, Share, Live Text — with only Copy/Cut/Paste's `onPressed`
  /// swapped to go through [controller]'s rich clipboard path instead of
  /// `EditableTextState`'s own plain-text-only default.
  ///
  /// This used to be reconstructed from scratch via
  /// `AdaptiveTextSelectionToolbar.editable(...)`, naming every button
  /// individually — `onLiveTextInput`, `onLookUp`, `onSearchWeb`, and
  /// `onShare` were all hardcoded to `null` (silently dropping those
  /// entries versus the platform's actual native menu), and
  /// `clipboardStatus` was hardcoded to `ClipboardStatus.pasteable`
  /// (showing "Paste" even with an empty clipboard, instead of the real,
  /// live clipboard-content check `EditableTextState` already does
  /// internally) — a real, reported bug ("doesn't look and behave like
  /// the native one"). Starting from `editableTextState
  /// .contextMenuButtonItems` — the exact list Flutter's own
  /// `AdaptiveTextSelectionToolbar.editableText` constructor uses — and
  /// only intercepting the three button *types* that need to route
  /// through this editor's own clipboard manager (for rich-formatting
  /// preservation; see `ClipboardManager`) means every other entry is
  /// genuinely, exactly what the platform's native toolbar would show,
  /// with zero risk of drifting out of sync as Flutter adds/changes
  /// button types in future versions.
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

  /// The selection toolbar shown unless a host supplies its own
  /// [contextMenuBuilder] — the platform-native button set (via
  /// [_richButtonItems]) plus Open/Edit/Remove whenever the selection is
  /// entirely inside a single link.
  ///
  /// "Entirely inside" is deliberate, not just "touches a link at
  /// `selection.start`" (the previous check): a real, reported bug —
  /// "Select All" on a note whose *first* paragraph happens to be a link
  /// showed the link-editing menu (Open/Edit/Remove) for a selection
  /// that actually spanned the whole document, most of which has
  /// nothing to do with that link. Open/Edit/Remove only make sense when
  /// the user is plausibly interacting with *that specific link* — a
  /// collapsed caret inside it, or a drag-selection that stays within
  /// its bounds — not whenever a selection's *start offset* merely
  /// happens to land inside one link while extending arbitrarily far
  /// beyond it.
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

    // Extracted so the ruled-lines painter can lay out through the exact
    // same style/strut the real `TextField` below uses — see
    // `TextSpanRenderer.lineBottomOffsets`. Built fresh each `build()`
    // (cheap, plain data objects with value equality), not cached here:
    // the cache that matters is the layout cache inside
    // `lineBottomOffsets` itself, keyed off these by value.
    final baseTextStyle = TextStyle(
      fontSize: renderTheme.baseFontSize,
      height: renderTheme.lineHeight / renderTheme.baseFontSize,
      color: Colors.black,
      letterSpacing: 0.2,
    );
    final strutStyle = StrutStyle(
      fontSize: renderTheme.baseFontSize,
      height: renderTheme.lineHeight / renderTheme.baseFontSize,
      // forceStrutHeight is deliberately false: a header's own line
      // height is quantized up to a whole multiple of
      // `renderTheme.lineHeight` (see `TextSpanRenderer
      // ._quantizedLineHeight`), so it's never *smaller* than what the
      // strut alone would provide for body text — this strut only ever
      // sets a floor for plain, unstyled text, never fights a header's
      // own (larger) requested height.
      leading: 0.0,
    );

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            // Single, shared left-padding animation — both the
            // ruled-lines width calc below and the real `TextField`'s
            // own padding read the *same* `leftPad` value from this one
            // builder, rather than two independently-ticking
            // `TweenAnimationBuilder`s driven by the same end value.
            // Two separate animations agreeing "closely enough" most of
            // the time isn't the same guarantee as one shared value
            // that can never disagree with itself.
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
                    // Positioned.fill (not a bare, non-positioned child)
                    // deliberately: every other child in this Stack is
                    // Positioned, so the Stack's own size is driven
                    // entirely by its ancestor's constraints. A single
                    // non-positioned child changes that -- Stack then
                    // also sizes itself to fit its non-positioned
                    // children, and a zero-size one (this renders
                    // nothing) can collapse the whole Stack to zero
                    // whenever the ancestor's constraints are loose
                    // rather than tight. Confirmed live: this collapsed
                    // the entire editor to an invisible 0×0 canvas the
                    // moment *any* non-positioned child — even a totally
                    // inert one with no logic at all — was added here,
                    // in the real browser specifically (constraints
                    // there came out loose; the widget-test
                    // reproduction happened to use a tightly-constrained
                    // ancestor, which masked it completely).
                    Positioned.fill(
                      child: _ScrollToCurrentMatch(
                        controller: controller,
                        scrollController: scrollController,
                        maxWidth: maxTextWidth,
                        style: baseTextStyle,
                        strutStyle: strutStyle,
                        topPadding: editorStyle.paddingTop,
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: showMargin ? 1.0 : 0.0),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOut,
                          builder: (context, marginOpacity, child) {
                            // Scoped to exactly what needs it — not the
                            // `TextField` subtree below, which stays
                            // outside any `ListenableBuilder(listenable:
                            // controller)` for the reason explained at
                            // the top of this method (selection-drag
                            // smoothness). This layer doesn't take part
                            // in that gesture at all, and the actual
                            // expensive step (re-laying-out text for
                            // `lineBottomOffsets`) is cached by content
                            // revision, so a selection-only notification
                            // here is a cheap cache hit, not a relayout.
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
                          // `TextField` has no `textHeightBehavior`
                          // parameter of its own -- `EditableText`/
                          // `RenderEditable` fall back to this ambient
                          // value when building their internal paragraph,
                          // which is the only way to reach it here. Must
                          // stay in sync with the `textHeightBehavior`
                          // passed to `lineBottomOffsets` above.
                          child: DefaultTextHeightBehavior(
                            textHeightBehavior: _kTextHeightBehavior,
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
                              style: baseTextStyle,
                              strutStyle: strutStyle,
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
                              contextMenuBuilder:
                                  contextMenuBuilder ??
                                  _defaultContextMenuBuilder,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Tap-triggered link preview — see LinkPreviewBar's own doc
                    // comment for why this is tap/fixed-position rather than
                    // hover/caret-anchored. Rebuilds on every controller
                    // notification (every selection change included), same
                    // pattern FormatToolbar already uses to stay in sync.
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
