import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/clipboard/clipboard_manager.dart';
import 'package:lightweight_rich_editor/src/clipboard/rich_clipboard_delegate.dart';
import 'package:lightweight_rich_editor/src/commands/command_dispatcher.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/core/editor_selection.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/history/history_manager.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

class _FakeRichClipboard implements RichClipboardDelegate {
  String? text;
  List<TextAttribute> attributes = const [];

  @override
  void store(String text, List<TextAttribute> attributes) {
    this.text = text;
    this.attributes = attributes;
  }

  @override
  ({String text, List<TextAttribute> attributes})? read() {
    if (text == null) return null;
    return (text: text!, attributes: attributes);
  }
}

({EditorDocument document, ClipboardManager clipboard}) _harness(
    String text, {
      RichClipboardDelegate? delegate,
    }) {
  final document = EditorDocument.fromText(text);
  final engine = EditingEngine(document: document, transactions: TransactionManager(() {}));
  final history = HistoryManager(engine: engine);
  final commands = CommandDispatcher(engine: engine, history: history);
  return (
  document: document,
  clipboard: ClipboardManager(document: document, commands: commands, delegate: delegate),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Explicitly mock the clipboard platform channel rather than relying
  // on flutter_test's default handling of it, which turned out not to
  // round-trip reliably (both tests below that read back what they
  // wrote failed against the default). This is the standard, version-
  // independent way to test Clipboard-dependent code.
  String? systemClipboardText;

  setUp(() {
    systemClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            systemClipboardText = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return {'text': systemClipboardText};
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ClipboardManager.copy', () {
    test('stores the selected text and offset-relative attributes in the delegate', () async {
      final delegate = _FakeRichClipboard();
      final h = _harness('hello world', delegate: delegate);
      h.document.attributeStore.insert(const TextAttribute(start: 6, end: 11, type: AttributeType.bold));

      await h.clipboard.copy(const EditorSelection(baseOffset: 6, extentOffset: 11));

      expect(delegate.text, 'world');
      expect(delegate.attributes, hasLength(1));
      expect(delegate.attributes.single.start, 0);
      expect(delegate.attributes.single.end, 5);
    });

    test('clips an attribute that only partially overlaps the selection', () async {
      final delegate = _FakeRichClipboard();
      final h = _harness('hello world', delegate: delegate);
      // Bold spans "lo wor" (3-9); copying "hello " (0-6) overlaps it at
      // 3-6, which relative to the selection start is 3-6.
      h.document.attributeStore.insert(const TextAttribute(start: 3, end: 9, type: AttributeType.bold));

      await h.clipboard.copy(const EditorSelection(baseOffset: 0, extentOffset: 6));

      expect(delegate.attributes.single.start, 3);
      expect(delegate.attributes.single.end, 6);
    });

    test('no-op on a collapsed selection — delegate is left untouched', () async {
      final delegate = _FakeRichClipboard();
      final h = _harness('hello world', delegate: delegate);

      await h.clipboard.copy(const EditorSelection.collapsed(3));

      expect(delegate.text, isNull);
    });
  });

  group('ClipboardManager.cut', () {
    test('copies then deletes the selection', () async {
      final delegate = _FakeRichClipboard();
      final h = _harness('hello world', delegate: delegate);

      await h.clipboard.cut(const EditorSelection(baseOffset: 0, extentOffset: 6));

      expect(delegate.text, 'hello ');
      expect(h.document.text, 'world');
    });
  });

  group('ClipboardManager.paste', () {
    test('returns null when the system clipboard has no text', () async {
      await Clipboard.setData(const ClipboardData(text: ''));
      final h = _harness('');

      final result = await h.clipboard.paste(const EditorSelection.collapsed(0));

      expect(result, isNull);
    });

    test('round-trips rich content when the delegate matches the system clipboard', () async {
      final delegate = _FakeRichClipboard();
      final h = _harness('hello world', delegate: delegate);
      h.document.attributeStore.insert(const TextAttribute(start: 0, end: 5, type: AttributeType.bold));

      await h.clipboard.copy(const EditorSelection(baseOffset: 0, extentOffset: 5)); // also sets system clipboard
      await h.clipboard.paste(const EditorSelection.collapsed(11));

      expect(h.document.text, 'hello worldhello');
      expect(h.document.attributeStore.coversRange(11, 16, AttributeType.bold), isTrue);
    });

    test('falls back to plain text when the delegate content does not match the system clipboard', () async {
      final delegate = _FakeRichClipboard();
      final h = _harness('', delegate: delegate);
      await Clipboard.setData(const ClipboardData(text: 'plain from elsewhere'));
      delegate.store('stale rich text', const [TextAttribute(start: 0, end: 3, type: AttributeType.bold)]);

      final result = await h.clipboard.paste(const EditorSelection.collapsed(0));

      expect(h.document.text, 'plain from elsewhere');
      expect(h.document.attributeStore.spans, isEmpty);
      expect(result, isNotNull);
    });
  });
}
