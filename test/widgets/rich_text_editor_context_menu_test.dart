import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/clipboard/rich_clipboard_delegate.dart';
import 'package:lightweight_rich_editor/src/controller/rich_editor_controller.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';
import 'package:lightweight_rich_editor/src/widgets/rich_text_editor.dart';

/// A [RichClipboardDelegate] test double that just records whether
/// [store] was ever called — enough to tell "the rich clipboard path
/// ran" apart from "`EditableTextState`'s own plain-text-only default
/// ran instead", without needing to inspect the real system clipboard.
class _RecordingDelegate implements RichClipboardDelegate {
  bool stored = false;

  @override
  void store(String text, List<TextAttribute> attributes) {
    stored = true;
  }

  @override
  ({String text, List<TextAttribute> attributes})? read() => null;
}

void main() {
  // Regression coverage for a real, reported bug. The menu shown when
  // the caret is inside a link prepends custom Open/Edit/Remove buttons
  // to the platform's own native button set — that trailing native set
  // used to be `editableTextState.contextMenuButtonItems` spread in
  // completely unmodified, meaning Copy (when a link selection is also
  // copyable) went through `EditableTextState`'s own plain-text-only
  // default instead of this editor's rich clipboard path — silently
  // inconsistent with the plain (no-link) menu, which always did route
  // Copy correctly. The fix runs the *same* `_richButtonItems` swap for
  // both menus, so Copy behaves identically regardless of whether the
  // selection happens to touch a link.
  testWidgets(
    "the link-selection toolbar's Copy button also routes through the rich clipboard delegate, not the plain-text default",
    (tester) async {
      final delegate = _RecordingDelegate();
      final controller = RichEditorController(
        text: 'visit example for more',
        initialAttributes: [
          const TextAttribute(
            start: 6,
            end: 13,
            type: AttributeType.link,
            value: 'https://example.com',
          ),
        ],
        richClipboardDelegate: delegate,
      );
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      const channel = MethodChannel(
        'com.kenresoft.lightweight_rich_editor/rich_clipboard',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              controller: controller,
              scrollController: scrollController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "example" (offsets 6-13) is the linked word — a non-collapsed
      // selection over it so the link branch fires and Copy is offered.
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 6, extentOffset: 13),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      final editableTextState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final toolbar = field.contextMenuBuilder!(tester.element(find.byType(TextField)), editableTextState);

      // Mount the built toolbar in a minimal host so its buttons actually
      // render and can be found/tapped, the same as the real overlay
      // Flutter shows would.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: toolbar)),
        ),
      );
      await tester.pumpAndSettle();

      final copyButton = find.text('Copy');
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(delegate.stored, isTrue);
    },
  );

  testWidgets(
    "the plain (no-link) selection toolbar's Copy button also routes through the rich clipboard delegate",
    (tester) async {
      final delegate = _RecordingDelegate();
      final controller = RichEditorController(
        text: 'hello world',
        richClipboardDelegate: delegate,
      );
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      const channel = MethodChannel(
        'com.kenresoft.lightweight_rich_editor/rich_clipboard',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              controller: controller,
              scrollController: scrollController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      final editableTextState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final toolbar = field.contextMenuBuilder!(tester.element(find.byType(TextField)), editableTextState);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: toolbar)),
        ),
      );
      await tester.pumpAndSettle();

      final copyButton = find.text('Copy');
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(delegate.stored, isTrue);
    },
  );

  // Regression test for a real, reported bug: "Select All" on a note
  // whose *first* paragraph is a link showed the link-editing menu
  // (Open/Edit/Remove) for a selection that actually spanned the whole
  // document — because the old check only asked "does a link sit at
  // `selection.start`?", true for any selection merely *starting*
  // inside one, however far it extends beyond it. The fix requires the
  // whole selection to fit inside the link's own range.
  testWidgets(
    'selecting well beyond a link (e.g. via Select All) shows the plain toolbar, not the link-editing menu',
    (tester) async {
      final controller = RichEditorController(
        text: 'example rest of the very long note continues here',
        initialAttributes: const [
          TextAttribute(start: 0, end: 7, type: AttributeType.link, value: 'https://example.com'),
        ],
      );
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      const channel = MethodChannel(
        'com.kenresoft.lightweight_rich_editor/rich_clipboard',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              controller: controller,
              scrollController: scrollController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulates Select All: a selection starting inside the link (like
      // offset 0 of Select All would, with the link as the first thing
      // in the document) but extending far past it.
      controller.value = controller.value.copyWith(
        selection: TextSelection(baseOffset: 0, extentOffset: controller.document.length),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      final editableTextState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final toolbar = field.contextMenuBuilder!(tester.element(find.byType(TextField)), editableTextState);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: toolbar)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
    },
  );

  testWidgets(
    'a selection collapsed inside a link still shows the link-editing menu',
    (tester) async {
      final controller = RichEditorController(
        text: 'visit example for more',
        initialAttributes: const [
          TextAttribute(start: 6, end: 13, type: AttributeType.link, value: 'https://example.com'),
        ],
      );
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      const channel = MethodChannel(
        'com.kenresoft.lightweight_rich_editor/rich_clipboard',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichTextEditor(
              controller: controller,
              scrollController: scrollController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 9),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      final editableTextState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final toolbar = field.contextMenuBuilder!(tester.element(find.byType(TextField)), editableTextState);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: toolbar)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    },
  );
}
