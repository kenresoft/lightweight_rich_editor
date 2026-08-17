import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Regression test for a real, reported bug: "internal" copy/paste
  // (within the app, not from some other app) was silently losing
  // formatting whenever the copy and the paste happened in two
  // *different* controller instances — e.g. copying from one note and
  // pasting into another, or reopening a note (a fresh controller) after
  // copying from it. Each `RichEditorController` used to default to its
  // own brand-new `InMemoryRichClipboardDelegate()`, so the rich content
  // stashed by controller A's copy was invisible to controller B's
  // paste — invisible even though both live in the very same app.
  //
  // The native/system clipboard round-trips plain text unconditionally
  // via `MethodChannel`, but never sends an `html` flavor here (the OS
  // plugin isn't present in a unit-test host) — mirroring the situation
  // this bug actually reproduces in real apps that haven't wired up an
  // OS-level HTML flavor at all (web, or a platform without the native
  // plugin), where the delegate is the *only* thing that can carry
  // formatting across the paste. If the delegate isn't shared, this
  // paste has no way to know "hello" used to be bold.
  test('copying in one controller and pasting into a different controller preserves formatting', () async {
    const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (methodCall) async {
        if (methodCall.method == 'setData') {
          clipboardText = (methodCall.arguments as Map)['text'] as String?;
          return null;
        }
        if (methodCall.method == 'getData') {
          return {'text': clipboardText, 'html': null};
        }
        return null;
      },
    );

    final controllerA = RichEditorController(text: 'hello world');
    controllerA.value = controllerA.value.copyWith(
      selection: const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    controllerA.toggleBold();
    await controllerA.copy();

    final controllerB = RichEditorController();
    await controllerB.paste();

    expect(controllerB.document.text, 'hello');
    expect(controllerB.document.attributes.any((a) => a.type == AttributeType.bold), isTrue);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
