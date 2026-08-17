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

      await clipboard.paste(const EditorSelection.collapsed(0));

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

  group('ClipboardManager.paste — autolinking a bare URL', () {
    const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');

    test('a bare URL alongside real HTML formatting still gets linkified', () async {
      // Regression test: a bare URL pasted as part of HTML content (no
      // <a> tag around it -- the common case for a URL copied from,
      // say, a browser's address bar alongside other rich content) used
      // to never reach the plain-text autolink fallback at all, since
      // choosing the HTML import path skipped it entirely.
      const html = '<b>Bold</b> visit https://example.com for more';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': 'Bold visit https://example.com for more', 'html': html};
        }
        return null;
      });

      await clipboard.paste(const EditorSelection.collapsed(0));

      expect(document.attributes.any((a) => a.type == AttributeType.bold), isTrue);
      final link = document.attributes.firstWhere((a) => a.type == AttributeType.link);
      expect(document.text.substring(link.start, link.end), 'https://example.com');
      expect(link.value, 'https://example.com');
    });

    test('a bare URL alongside Markdown formatting still gets linkified', () async {
      const markdown = '# Title\nVisit https://example.com for more';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': markdown, 'html': ''};
        }
        return null;
      });

      await clipboard.paste(const EditorSelection.collapsed(0));

      expect(document.attributes.any((a) => a.type == AttributeType.header), isTrue);
      final link = document.attributes.firstWhere((a) => a.type == AttributeType.link);
      expect(document.text.substring(link.start, link.end), 'https://example.com');
    });

    test('an HTML anchor is not double-linked by the autolink pass', () async {
      const html = '<a href="https://example.com">https://example.com</a>';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': 'https://example.com', 'html': html};
        }
        return null;
      });

      await clipboard.paste(const EditorSelection.collapsed(0));

      expect(document.attributes.where((a) => a.type == AttributeType.link).length, 1);
    });

    // Regression test for a real, reported bug: pasting multi-line plain
    // text with '\r\n' line endings (what Windows' clipboard normally
    // provides, confirmed in real testing) failed to linkify *any* URL
    // in the text, not just the one on the affected line. '\r' isn't a
    // recognized autolink boundary character, so it got absorbed into
    // each token as part of the "word", which in turn defeated the
    // trailing-punctuation trim (anchored at the string's end, now '\r'
    // instead of the comma before it) and left a raw control character
    // embedded in what got handed to Uri.tryParse — failing to parse for
    // every line.
    test('URLs in \\r\\n-delimited pasted text are still linkified', () async {
      const pasted = 'Production Apps:\r\n'
          'https://play.google.com/store/apps/details?id=com.phunplan.phunplan, \r\n'
          'https://apps.apple.com/app/6763565579,\r\n'
          'https://play.google.com/store/apps/details?id=com.telomii.telomii,\r\n'
          'https://play.google.com/store/apps/details?id=com.lfb.desktopbrowser';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getData') {
          return {'text': pasted, 'html': ''};
        }
        return null;
      });

      await clipboard.paste(const EditorSelection.collapsed(0));

      final links = document.attributes.where((a) => a.type == AttributeType.link).toList();
      expect(links, hasLength(4));
      expect(links[0].value, 'https://play.google.com/store/apps/details?id=com.phunplan.phunplan');
      expect(links[1].value, 'https://apps.apple.com/app/6763565579');
      expect(links[2].value, 'https://play.google.com/store/apps/details?id=com.telomii.telomii');
      expect(links[3].value, 'https://play.google.com/store/apps/details?id=com.lfb.desktopbrowser');
      // The pasted text itself is normalized to '\n' too -- otherwise a
      // stray '\r' would survive in the document text even once linking
      // was fixed.
      expect(document.text.contains('\r'), isFalse);
    });
  });
}
