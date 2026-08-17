import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/controller/rich_editor_controller.dart';
import 'package:lightweight_rich_editor/src/widgets/lightweight_rich_editor.dart';

void main() {
  group('LightweightRichEditor — internally-owned controller', () {
    testWidgets('seeds the editor with initialText', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LightweightRichEditor(initialText: 'hello world')),
      ));

      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets('exposes the internally-created controller via a GlobalKey', (tester) async {
      final key = GlobalKey<LightweightRichEditorState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LightweightRichEditor(key: key, initialText: 'hi')),
      ));

      expect(key.currentState!.controller.document.text, 'hi');
    });

    testWidgets('disposes the controller it created when unmounted', (tester) async {
      final key = GlobalKey<LightweightRichEditorState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LightweightRichEditor(key: key, initialText: 'hi')),
      ));
      final controller = key.currentState!.controller;

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

      // A disposed ChangeNotifier throws on addListener.
      expect(() => controller.addListener(() {}), throwsA(anything));
    });

    testWidgets('toolbar Save/Load buttons are hidden when callbacks are omitted', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LightweightRichEditor()),
      ));

      expect(find.byTooltip('Save Note'), findsNothing);
      expect(find.byTooltip('Load Note'), findsNothing);
    });

    testWidgets('toolbar Save/Load buttons appear and fire when callbacks are provided', (tester) async {
      var saved = false;
      var loaded = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LightweightRichEditor(
            onSave: () => saved = true,
            onLoad: () => loaded = true,
          ),
        ),
      ));

      await tester.tap(find.byTooltip('Save Note'));
      await tester.tap(find.byTooltip('Load Note'));
      await tester.pump();

      expect(saved, isTrue);
      expect(loaded, isTrue);
    });

    testWidgets('the find button toggles the find bar', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LightweightRichEditor(initialText: 'find me')),
      ));

      expect(find.byTooltip('Find & Replace'), findsOneWidget);
      expect(find.text('Find'), findsNothing);

      await tester.tap(find.byTooltip('Find & Replace'));
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Find'), findsOneWidget);
    });
  });

  group('LightweightRichEditor — externally-supplied controller', () {
    testWidgets('uses the supplied controller rather than creating a new one', (tester) async {
      final controller = RichEditorController(text: 'external');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LightweightRichEditor(controller: controller)),
      ));

      expect(find.text('external'), findsOneWidget);
    });

    testWidgets('does not dispose a supplied controller on unmount', (tester) async {
      final controller = RichEditorController(text: 'external');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LightweightRichEditor(controller: controller)),
      ));

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

      // Still usable -- addListener would throw on a disposed controller.
      expect(() => controller.addListener(() {}), returnsNormally);
      controller.dispose();
    });
  });

  group('RichEditorController.reclaimFocus', () {
    testWidgets('leaves the editor focused after a host-owned button steals focus', (tester) async {
      final key = GlobalKey<LightweightRichEditorState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.dark_mode),
                  onPressed: () {
                    // Simulates a host's own UI (outside FormatToolbar)
                    // that needs the same fix FormatToolbar's own
                    // buttons already get internally.
                    key.currentState!.controller.reclaimFocus();
                  },
                ),
              ),
            ],
          ),
          body: LightweightRichEditor(key: key, initialText: 'hello'),
        ),
      ));

      final controller = key.currentState!.controller;
      controller.focusNode.requestFocus();
      await tester.pump();
      expect(controller.focusNode.hasFocus, isTrue);

      await tester.tap(find.byIcon(Icons.dark_mode));
      await tester.pump();

      expect(controller.focusNode.hasFocus, isTrue);
    });
  });
}
