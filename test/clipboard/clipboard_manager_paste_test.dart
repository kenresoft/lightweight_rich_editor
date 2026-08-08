import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/clipboard/clipboard_manager.dart';
import 'package:lightweight_rich_editor/src/commands/command_dispatcher.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/core/editor_selection.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/history/history_manager.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorDocument document;
  late EditingEngine engine;
  late CommandDispatcher commands;
  late ClipboardManager clipboard;

  setUp(() {
    document = EditorDocument();
    final transactions = TransactionManager(() {});
    engine = EditingEngine(document: document, transactions: transactions);
    final history = HistoryManager(engine: engine);
    commands = CommandDispatcher(engine: engine, history: history);
    clipboard = ClipboardManager(document: document, commands: commands);
  });

  group('ClipboardManager.paste heuristic detection', () {
    const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');

    test('detects and imports HTML', () async {
      const html = '<b>Bold</b> text';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': 'Bold text', 'html': html};
        }
        return null;
      });

      final result = await clipboard.paste(const EditorSelection.collapsed(0));
      
      expect(document.text, 'Bold text');
      expect(document.attributes.any((a) => a.type == AttributeType.bold), isTrue);
    });

    test('detects and imports Markdown', () async {
      const markdown = '# Title\n**bold**';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': markdown, 'html': ''};
        }
        return null;
      });

      await clipboard.paste(const EditorSelection.collapsed(0));
      
      expect(document.text, 'Title\nbold');
      expect(document.attributes.any((a) => a.type == AttributeType.header), isTrue);
      expect(document.attributes.any((a) => a.type == AttributeType.bold), isTrue);
    });

    test('falls back to plain text if no markers found', () async {
      const plain = 'Just some text';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': plain, 'html': ''};
        }
        return null;
      });

      await clipboard.paste(const EditorSelection.collapsed(0));
      
      expect(document.text, plain);
      expect(document.attributes, isEmpty);
    });

    test('prefers HTML over Markdown if both look present', () async {
      const mixed = '<b>Bold</b> and **Markdown**';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': 'Bold and **Markdown**', 'html': mixed};
        }
        return null;
      });

      await clipboard.paste(const EditorSelection.collapsed(0));
      
      expect(document.text, 'Bold and **Markdown**');
      expect(document.attributes.any((a) => a.type == AttributeType.bold), isTrue);
    });
  });
}
