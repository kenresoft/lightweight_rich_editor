// Link opening: URL normalization/validation, the launcher, and the editor
// path from a tap on a rendered link to the platform launcher.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final launched = <String>[];
  bool canOpen = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => canOpen;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

TextAttribute link(int s, int e, String url) => TextAttribute(start: s, end: e, type: AttributeType.link, value: url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLauncher fake;
  setUp(() {
    fake = FakeLauncher();
    UrlLauncherPlatform.instance = fake;
  });

  group('normalizeLinkUri', () {
    test('http and https are kept', () {
      expect(normalizeLinkUri('https://kenresoft.com/blog?a=1#x').toString(), 'https://kenresoft.com/blog?a=1#x');
      expect(normalizeLinkUri('http://example.com').toString(), 'http://example.com');
      expect(normalizeLinkUri('  https://example.com  ').toString(), 'https://example.com');
    });

    test('scheme-less domains open as https, bare emails as mailto', () {
      expect(normalizeLinkUri('www.example.com').toString(), 'https://www.example.com');
      expect(normalizeLinkUri('example.com/path').toString(), 'https://example.com/path');
      expect(normalizeLinkUri('localhost.dev:8080/x').toString(), 'https://localhost.dev:8080/x');
      expect(normalizeLinkUri('me@example.com').toString(), 'mailto:me@example.com');
    });

    test('mailto: and tel: are allowed', () {
      expect(normalizeLinkUri('mailto:me@example.com').toString(), 'mailto:me@example.com');
      expect(normalizeLinkUri('tel:+15551234').toString(), 'tel:+15551234');
    });

    test('invalid or unsafe links are refused', () {
      for (final bad in ['', '   ', 'not a url', 'javascript:alert(1)', 'file:///etc/passwd', 'intent://x#Intent;end', 'https://', 'just-a-word', 'data:text/html,hi']) {
        expect(normalizeLinkUri(bad), isNull, reason: bad);
      }
    });
  });

  group('launchLinkUrl', () {
    test('launches a valid URL externally and reports success', () async {
      expect(await launchLinkUrl('https://kenresoft.com'), isTrue);
      expect(fake.launched, ['https://kenresoft.com']);
    });

    test('normalizes before launching', () async {
      expect(await launchLinkUrl('kenresoft.com'), isTrue);
      expect(fake.launched, ['https://kenresoft.com']);
    });

    test('invalid, unsafe or unlaunchable links are swallowed (false), never thrown', () async {
      expect(await launchLinkUrl('javascript:alert(1)'), isFalse);
      expect(await launchLinkUrl('nope'), isFalse);
      fake.canOpen = false;
      expect(await launchLinkUrl('https://kenresoft.com'), isFalse);
      expect(fake.launched, isEmpty);
    });
  });

  group('in the editor', () {
    const text = 'see the docs now';

    Future<void> pump(
      WidgetTester tester,
      RichEditorController c, {
      bool openLinksOnTap = false,
      double width = 600,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RichTextEditor(
            controller: c,
            scrollController: ScrollController(),
            autofocus: false,
            openLinksOnTap: openLinksOnTap,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Offset glyph(WidgetTester tester, int offset) {
      final render = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
      final a = render.getLocalRectForCaret(TextPosition(offset: offset));
      final b = render.getLocalRectForCaret(TextPosition(offset: offset + 1));
      return render.localToGlobal(Offset((a.left + b.left) / 2, a.center.dy));
    }

    testWidgets('a tap on a link glyph asks to open it; Open launches the (normalized) URL', (tester) async {
      final c = RichEditorController(text: text, initialAttributes: [link(8, 12, 'kenresoft.com/docs')]);
      addTearDown(c.dispose);
      await pump(tester, c, openLinksOnTap: true);
      await tester.tapAt(glyph(tester, 9));
      await tester.pumpAndSettle();
      expect(find.text('Open link?'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(fake.launched, ['https://kenresoft.com/docs']);
      expect(c.selection.isCollapsed, isTrue, reason: 'the tap still placed the caret');
    });

    testWidgets('with a custom onTapLink the tap goes to it directly (no dialog)', (tester) async {
      final tapped = <String>[];
      final c = RichEditorController(
        text: text,
        initialAttributes: [link(8, 12, 'https://kenresoft.com/docs')],
        onTapLink: tapped.add,
      );
      addTearDown(c.dispose);
      await pump(tester, c, openLinksOnTap: true);
      await tester.tapAt(glyph(tester, 10));
      await tester.pumpAndSettle();
      expect(tapped, ['https://kenresoft.com/docs']);
      expect(find.text('Open link?'), findsNothing);
    });

    testWidgets('taps on plain text, or in the empty space after a link ends a line, open nothing', (tester) async {
      final tapped = <String>[];
      final c = RichEditorController(
        text: 'see the docs',
        initialAttributes: [link(8, 12, 'https://kenresoft.com/docs')],
        onTapLink: tapped.add,
      );
      addTearDown(c.dispose);
      await pump(tester, c, openLinksOnTap: true);
      await tester.tapAt(glyph(tester, 1));
      await tester.pumpAndSettle();
      final render = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
      final end = render.getLocalRectForCaret(const TextPosition(offset: 12));
      await tester.tapAt(render.localToGlobal(Offset(end.right + 120, end.center.dy)));
      await tester.pumpAndSettle();
      expect(tapped, isEmpty);
    });

    testWidgets('a drag or a long press on a link does not open it (selection gestures stay selection)', (tester) async {
      final tapped = <String>[];
      final c = RichEditorController(
        text: text,
        initialAttributes: [link(8, 12, 'https://kenresoft.com/docs')],
        onTapLink: tapped.add,
      );
      addTearDown(c.dispose);
      await pump(tester, c, openLinksOnTap: true);
      await tester.dragFrom(glyph(tester, 8), const Offset(40, 0));
      await tester.pumpAndSettle();
      await tester.longPressAt(glyph(tester, 10));
      await tester.pumpAndSettle();
      expect(tapped, isEmpty);
    });

    testWidgets('openLinksOnTap is off by default: a tap only places the caret', (tester) async {
      final tapped = <String>[];
      final c = RichEditorController(
        text: text,
        initialAttributes: [link(8, 12, 'https://kenresoft.com/docs')],
        onTapLink: tapped.add,
      );
      addTearDown(c.dispose);
      await pump(tester, c);
      await tester.tapAt(glyph(tester, 10));
      await tester.pumpAndSettle();
      expect(tapped, isEmpty);
      expect(fake.launched, isEmpty);
    });

    testWidgets('a link wrapped over two lines opens from either line', (tester) async {
      const long = 'aaaa bbbb cccc dddd eeee ffff';
      final tapped = <String>[];
      final c = RichEditorController(
        text: long,
        initialAttributes: [link(0, long.length, 'https://kenresoft.com/x')],
        onTapLink: tapped.add,
      );
      addTearDown(c.dispose);
      // Narrow enough to wrap the text onto several lines.
      await pump(tester, c, openLinksOnTap: true, width: 160);
      final render = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
      final first = render.getLocalRectForCaret(const TextPosition(offset: 1));
      final last = render.getLocalRectForCaret(const TextPosition(offset: 26));
      expect(last.top, greaterThan(first.top), reason: 'test setup: the link must wrap');
      await tester.tapAt(glyph(tester, 1));
      await tester.pumpAndSettle();
      await tester.tapAt(glyph(tester, 26));
      await tester.pumpAndSettle();
      expect(tapped, ['https://kenresoft.com/x', 'https://kenresoft.com/x']);
    });

    testWidgets('caret inside a link shows the preview bar; its Open button confirms and launches', (tester) async {
      final c = RichEditorController(
        text: text,
        initialAttributes: [link(8, 12, 'https://kenresoft.com/docs')],
      );
      addTearDown(c.dispose);
      await pump(tester, c);
      c.selection = const TextSelection.collapsed(offset: 10);
      await tester.pumpAndSettle();
      expect(find.text('https://kenresoft.com/docs'), findsOneWidget);
      await tester.tap(find.byTooltip('Open link'));
      await tester.pumpAndSettle();
      expect(find.text('Open link?'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(fake.launched, ['https://kenresoft.com/docs']);
    });

    testWidgets('Cancel does not launch', (tester) async {
      final c = RichEditorController(text: text, initialAttributes: [link(8, 12, 'https://kenresoft.com')]);
      addTearDown(c.dispose);
      await pump(tester, c);
      c.selection = const TextSelection.collapsed(offset: 10);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.launched, isEmpty);
    });

    testWidgets('an unopenable link says so instead of failing silently', (tester) async {
      final c = RichEditorController(text: text, initialAttributes: [link(8, 12, 'javascript:alert(1)')]);
      addTearDown(c.dispose);
      await pump(tester, c);
      c.selection = const TextSelection.collapsed(offset: 10);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't open this link"), findsOneWidget);
      expect(fake.launched, isEmpty);
    });

    testWidgets('link styling is unchanged: underlined, link colour', (tester) async {
      final c = RichEditorController(text: text, initialAttributes: [link(8, 12, 'https://kenresoft.com')]);
      addTearDown(c.dispose);
      final span = c.renderer.renderSpan(c.document, style: const TextStyle(fontSize: 16));
      final run = span.children!.cast<TextSpan>().firstWhere((s) => s.text == 'docs');
      expect(run.style!.decoration, TextDecoration.underline);
      expect(run.style!.color, c.renderer.theme.linkColor);
    });
  });
}
