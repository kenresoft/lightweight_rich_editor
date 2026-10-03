// Pictures end to end: what is stored, copied and exported, the decode cache,
// and what the paper layer draws.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/core/editor_selection.dart';
import 'package:lightweight_rich_editor/src/export/html_exporter.dart';
import 'package:lightweight_rich_editor/src/export/markdown_exporter.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';

import '../rendering/notebook_policy_test.dart' show lay;
import '../support/notebook_test_support.dart';

// A 1x1 PNG.
final Uint8List _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class FakeStore extends RichImageStore {
  final Map<String, Uint8List> files = {};
  int loads = 0;
  int _n = 0;

  @override
  Future<String> save(Uint8List bytes) async {
    final id = 'img${++_n}';
    files[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> load(String id) async {
    loads++;
    return files[id];
  }
}

// Records the alpha of every horizontal rule, by y.
class _RuleCanvas implements Canvas {
  _RuleCanvas(this.strengths);
  final Map<double, double> strengths;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if (p1.dy == p2.dy) strengths[p1.dy] = paint.color.a;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _Canvas implements Canvas {
  final images = <Rect>[];
  final rrects = <RRect>[];
  @override
  void drawImageRect(dynamic image, Rect src, Rect dst, Paint paint) => images.add(dst);

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects.add(rrect);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

// Waits (in real time) for [condition], polling, instead of a fixed delay that
// breaks on a loaded machine.
Future<void> _until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);

  RichEditorController make(String text) => RichEditorController(text: text, theme: notebookTheme);

  group('export and import', () {
    test('an image block is one element with its id and rows; it round-trips and re-exports identically', () {
      final c = make('intro');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic1', rows: 4);
      final html = const HtmlExporter().export(c.text, c.document.exportAttributes());
      expect(html, contains('data-rich-image="img:pic1:'));
      expect(html, contains('data-rows="4"'));
      final parsed = const HtmlImporter().parse(html);
      final c2 = RichEditorController(text: parsed.text, initialAttributes: parsed.attributes);
      addTearDown(c2.dispose);
      final run = c2.imageRunAt(parsed.text.indexOf('\n') + 1)!;
      expect(run.id, 'pic1');
      expect(run.rows, 4);
      final again = const HtmlExporter().export(c2.text, c2.document.exportAttributes());
      expect(again, html, reason: 'stable: no blank line grows per cycle');
    });

    test('a hostile data-rich-image value is ignored', () {
      final parsed = const HtmlImporter().parse('<p>a</p><div data-rich-image="img:../../x:1" data-rows="3"></div><p>b</p>');
      expect(parsed.text, 'a\n\nb', reason: 'two paragraphs, and nothing for the bad block');
    });

    test('Markdown names the picture', () {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic1', rows: 3);
      expect(const MarkdownExporter().export(c.text, c.document.exportAttributes()), contains('![image](rich-image:pic1)'));
    });

    test('plain text is just blank lines: no placeholder characters anywhere', () {
      final c = make('a');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 1);
      c.insertImageBlock('pic1', rows: 3);
      expect(c.text.runes.every((r) => r == 0x0A || r == 0x61), isTrue);
    });
  });

  group('copy and paste inside the editor', () {
    test('a copied picture pastes as its own block, even right under the original', () async {
      final c = make('');
      addTearDown(c.dispose);
      const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');
      String? text;
      String? html;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setData') {
          text = (call.arguments as Map)['text'] as String?;
          html = (call.arguments as Map)['html'] as String?;
          return null;
        }
        if (call.method == 'getData') return {'text': text, 'html': html};
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      c.insertImageBlock('same', rows: 3); // rows 0..2, caret on the line after
      final run = c.imageRunAt(0)!;
      await c.clipboard.copy(EditorSelection(baseOffset: run.start, extentOffset: run.end));
      expect(html, contains('data-rich-image'));
      c.selection = const TextSelection.collapsed(offset: 3);
      await c.paste();

      final runs = <ImageRun>{};
      for (var i = 0; i < c.document.length; i++) {
        final r = c.imageRunAt(i);
        if (r != null) runs.add(r);
      }
      expect(runs.length, 2, reason: 'two blocks, not one tall block');
      expect(runs.map((r) => r.id).toSet(), {'same'});
      expect(runs.map((r) => r.level).toSet().length, 2, reason: 'each has its own instance tag');
    });
  });

  group('cache', () {
    testWidgets('decodes once, serves from memory, and reports a missing picture as failed', (tester) async {
      final store = FakeStore()..files['a'] = _png;
      final cache = RichImageCache(store);
      addTearDown(cache.dispose);
      await tester.runAsync(() async {
        expect(cache.peek('a'), isNull);
        cache.ensure('a', 100);
        cache.ensure('a', 100); // a second ask while loading costs nothing
        await _until(() => cache.peek('a') != null);
      });
      expect(cache.peek('a'), isNotNull);
      expect(store.loads, 1);
      cache.ensure('a', 100); // already there: no reload
      expect(store.loads, 1);

      await tester.runAsync(() async {
        cache.ensure('gone', 100);
        await _until(() => cache.hasFailed('gone'));
      });
      expect(cache.hasFailed('gone'), isTrue);
      expect(cache.peek('gone'), isNull);
    });

    testWidgets('stays within its memory budget, dropping the least recently used picture', (tester) async {
      final store = FakeStore();
      for (final id in ['a', 'b', 'c']) {
        store.files[id] = _png;
      }
      // Room for two decoded 1x1 pictures (4 bytes each) only.
      final cache = RichImageCache(store, maxBytes: 8);
      addTearDown(cache.dispose);
      await tester.runAsync(() async {
        for (final id in ['a', 'b']) {
          cache.ensure(id, 10);
          await _until(() => cache.peek(id) != null);
        }
        cache.peek('a'); // a is now more recent than b
        cache.ensure('c', 10);
        await _until(() => cache.peek('c') != null);
      });
      expect(cache.cachedBytes, lessThanOrEqualTo(8));
      expect(cache.peek('b'), isNull, reason: 'the least recently used went');
      expect(cache.peek('a'), isNotNull);
      expect(cache.peek('c'), isNotNull);
    });

    testWidgets('prepareImage reads the size and keeps a small picture as it is', (tester) async {
      final prepared = await tester.runAsync(() => prepareImage(_png));
      expect(prepared, isNotNull);
      expect(prepared!.width, 1);
      expect(prepared.height, 1);
      expect(prepared.bytes, _png);
      final bad = await tester.runAsync(() => prepareImage(Uint8List.fromList([1, 2, 3, 4])));
      expect(bad, isNull);
    });

    testWidgets('insertImageBytes stores the picture and inserts a block sized from its aspect', (tester) async {
      final store = FakeStore();
      final c = make('')..imageStore = store;
      addTearDown(c.dispose);
      final ok = await tester.runAsync(() => c.insertImageBytes(_png));
      expect(ok, isTrue);
      expect(store.files.length, 1);
      final run = c.imageRunAt(0)!;
      expect(run.id, 'img1');
      expect(run.rows, rowsForImage(1, 1));
      final notAPicture = await tester.runAsync(() => c.insertImageBytes(Uint8List.fromList([9, 9, 9])));
      expect(notAPicture, isFalse);
      expect(store.files.length, 1, reason: 'nothing stored for a non-picture');
    });

    testWidgets('a copied picture beside its own web address is a picture; beside real text it is text; Paste image forces it', (tester) async {
      Future<void> mockClipboard(String? text) async {
        const channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getImage') return _png;
          if (call.method == 'getData') return {'text': text, 'html': null};
          return null;
        });
      }

      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard'),
            null,
          ));

      Future<bool> paste(String? text, {bool force = false}) async {
        await mockClipboard(text);
        final c = make('')..imageStore = FakeStore();
        addTearDown(c.dispose);
        final ok = await tester.runAsync(() => c.pasteImageFromClipboard(force: force));
        return ok!;
      }

      expect(await paste(null), isTrue, reason: 'an image alone');
      expect(await paste('https://kenresoft.com/blog/hero.webp'), isTrue, reason: 'Chrome: the picture and its address');
      expect(await paste('some words I copied'), isFalse, reason: 'real text wins on a plain paste');
      expect(await paste('some words I copied', force: true), isTrue, reason: 'but Paste image is explicit');
    });

    testWidgets('without a store images are ignored', (tester) async {
      final c = make('');
      addTearDown(c.dispose);
      final ok = await tester.runAsync(() => c.insertImageBytes(_png));
      expect(ok, isFalse);
      expect(c.pasteImageFromClipboard(), completion(isFalse));
    });
  });

  group('painting', () {
    test('a decoded picture is drawn inside its rows, contained and never distorted; a pending one is a quiet card', () async {
      final c = make('');
      addTearDown(c.dispose);
      c.insertImageBlock('pic', rows: 4);
      final l = lay(c.text, attrs: c.document.exportAttributes(), dpr: 1.0);
      final canvas = _Canvas();
      RuledLinesPainter(
        lineBottoms: l.bottoms,
        imageBlocks: l.renderer.imageBlocks,
        imageLeft: 20,
        imageRight: 320,
        fallbackLineHeight: l.pitch,
        topPadding: 12,
        scrollOffset: 0,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.none,
        marginLineX: 44,
      ).paint(canvas, const Size(400, 600));
      expect(canvas.images, isEmpty, reason: 'nothing decoded yet');
      expect(canvas.rrects, isNotEmpty, reason: 'the placeholder card');
    });

    testWidgets('the paper layer repaints when a picture finishes decoding (no other change needed)', (tester) async {
      final store = FakeStore()..files['pic'] = _png;
      final cache = RichImageCache(store);
      addTearDown(cache.dispose);
      final painter = RuledLinesPainter(
        lineBottoms: const [],
        imageCache: cache,
        fallbackLineHeight: 30,
        topPadding: 12,
        scrollOffset: 0,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.none,
        marginLineX: 44,
      );
      var repaints = 0;
      painter.addListener(() => repaints++);
      await tester.runAsync(() async {
        cache.ensure('pic', 100);
        await _until(() => repaints > 0);
      });
      expect(repaints, greaterThan(0), reason: 'a decoded picture must be painted without waiting for an edit');
    });

    test('rules inside a picture block are drawn faintly; rules elsewhere keep full strength', () {
      final c = make('top\n');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 4);
      c.insertImageBlock('pic', rows: 4);
      final l = lay(c.text, attrs: c.document.exportAttributes(), dpr: 1.0);
      final strengths = <double, double>{};
      final canvas = _RuleCanvas(strengths);
      RuledLinesPainter(
        lineBottoms: l.bottoms,
        imageBlocks: l.renderer.imageBlocks,
        fallbackLineHeight: l.pitch,
        topPadding: 12,
        scrollOffset: 0,
        marginOpacity: 0,
        lineStyle: RuledLineStyle.solid,
        marginLineX: 44,
        lineColor: const Color(0xFF607D8B),
      ).paint(canvas, const Size(400, 600));
      final block = l.renderer.imageBlocks.single;
      final inside = strengths.entries.where((e) => e.key > 12 + block.top + 0.5 && e.key <= 12 + block.bottom + 0.5).toList();
      final outside = strengths.entries.where((e) => e.key <= 12 + block.top + 0.5 || e.key > 12 + block.bottom + 0.5).toList();
      expect(inside, hasLength(4));
      expect(inside.every((e) => e.value < 0.5), isTrue, reason: 'faint inside the block');
      expect(outside.every((e) => e.value == 1.0), isTrue, reason: 'full strength on the ruled page around it');
    });

    test('imageDestination fits without distortion, in the top-left corner', () {
      const area = Rect.fromLTWH(20, 100, 300, 120);
      final wide = RuledLinesPainter.imageDestination(area, const Size(600, 100)); // wider than tall
      expect(wide.width, 300);
      expect(wide.height, 50);
      expect(wide.left, 20);
      expect(wide.top, area.top, reason: 'spare room goes below the picture, not above it');
      final tall = RuledLinesPainter.imageDestination(area, const Size(100, 600));
      expect(tall.height, 120);
      expect(tall.width, closeTo(20, 0.01));
      expect(tall.left, 20);
    });
  });

  group('the editor', () {
    var removedCalls = 0;

    Future<(RichEditorController, FakeStore)> pumpEditor(WidgetTester tester) async {
      removedCalls = 0;
      final store = FakeStore()..files['pic'] = _png;
      final c = make('hello')..imageStore = store;
      addTearDown(c.dispose);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(body: RichTextEditor(controller: c, scrollController: ScrollController(), autofocus: false, onImageRemoved: () => removedCalls++)),
      ));
      await tester.pump();
      return (c, store);
    }

    testWidgets('a picture is requested only once it is near the screen, and the paper layer repaints when it arrives', (tester) async {
      final (c, store) = await pumpEditor(tester);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic', rows: 4);
      await tester.pump();
      await tester.runAsync(() => _until(() => c.imageCache!.peek('pic') != null));
      await tester.pump();
      expect(store.loads, 1);
      expect(c.imageCache!.peek('pic'), isNotNull);
    });

    testWidgets('selecting a picture shows its bar (hides the caret); Remove works and tells the host', (tester) async {
      final (c, _) = await pumpEditor(tester);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic', rows: 5);
      await tester.pump();
      expect(find.byTooltip('Remove picture'), findsNothing, reason: 'the caret is on the line after, not on the picture');

      final run = c.imageRunAt(6)!;
      c.focusNode.requestFocus();
      c.selection = TextSelection.collapsed(offset: run.start);
      await tester.pump();
      expect(find.byTooltip('Remove picture'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).showCursor, isFalse);
      // Every control is a comfortable touch target.
      final size = tester.getSize(find.ancestor(of: find.byIcon(Icons.delete_outline_rounded), matching: find.byType(InkWell)).first);
      expect(size.shortestSide, greaterThanOrEqualTo(44));

      await tester.tap(find.byTooltip('Remove picture'));
      await tester.pump();
      expect(c.document.paragraphs.hasAnyImage, isFalse);
      expect(c.text, 'hello\n', reason: 'back to the text it was');
      expect(find.byTooltip('Remove picture'), findsNothing);
      expect(removedCalls, 1, reason: 'the host is told, to offer Undo');
      c.undo();
      expect(c.document.paragraphs.hasAnyImage, isTrue, reason: 'and Undo brings it back');
    });

    testWidgets('cutting a selected picture removes all of it, not just its line breaks', (tester) async {
      final (c, _) = await pumpEditor(tester);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic', rows: 5);
      await tester.pump();
      final run = c.imageRunAt(6)!;
      c.selection = TextSelection(baseOffset: run.start, extentOffset: run.end);
      await tester.runAsync(c.cut);
      await tester.pump();
      expect(c.document.paragraphs.hasAnyImage, isFalse, reason: 'no shorter picture left behind');
      expect(c.text, 'hello\n');
    });

    testWidgets('named sizes: S / M / L / Full set the picture\'s width, the active one is marked, and the bar never covers the picture', (tester) async {
      final (c, _) = await pumpEditor(tester);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic', rows: 14); // more rows than a square picture needs for the full width
      await tester.pump();
      await tester.runAsync(() => _until(() => c.imageCache!.peek('pic') != null));
      c.focusNode.requestFocus();
      c.selection = TextSelection.collapsed(offset: c.imageRunAt(6)!.start);
      await tester.pump();
      await tester.pump();

      int rows() => c.imageRunAt(6)!.rows;
      Future<void> settle() async {
        await tester.pump();
        await tester.pump();
      }

      expect(find.text('Full'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      final spare = rows();

      // Full drops the spare room (no bigger picture, no wasted rows).
      await tester.tap(find.text('Full'));
      await settle();
      final full = rows();
      expect(full, lessThan(spare));
      expect(c.document.paragraphs.records.where((r) => isImageLevel(r.headerLevel)).length, full, reason: 'one whole block, nothing left over');

      // Each size is its own, increasing, row count.
      final seen = <String, int>{};
      for (final label in ['S', 'M', 'L', 'Full']) {
        if (find.text(label).evaluate().isEmpty) continue; // sizes that coincide are shown once
        await tester.tap(find.text(label));
        await settle();
        seen[label] = rows();
      }
      expect(seen['S'], lessThan(seen['Full']!));
      expect(seen['Full'], full);
      final ordered = seen.values.toList();
      expect([...ordered]..sort(), ordered, reason: 'S <= M <= L <= Full');

      // The bar is under (or over) the picture, never on it.
      await tester.tap(find.text('Full'));
      await settle();
      final region = c.renderer.imageBlocks.single;
      final editableTop = tester.getTopLeft(find.byType(EditableText)).dy;
      final pictureTop = editableTop + region.top + RuledLinesPainter.imageInset;
      final pictureBottom = pictureTop + region.height - 2 * RuledLinesPainter.imageInset;
      final bar = tester.getRect(find.ancestor(of: find.byIcon(Icons.delete_outline_rounded), matching: find.byType(Material)).first);
      expect(bar.top >= pictureBottom - 1 || bar.bottom <= pictureTop + 1, isTrue, reason: 'bar $bar vs picture $pictureTop..$pictureBottom');
    });

    testWidgets('a full-width picture stays full when the margin goes off (the column widens); a smaller one is left alone', (tester) async {
      final store = FakeStore()..files['pic'] = _png;
      final c = make('hello')..imageStore = store;
      addTearDown(c.dispose);
      final scroll = ScrollController();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      Widget editor(bool margin) => MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: Scaffold(body: RichTextEditor(controller: c, scrollController: scroll, autofocus: false, showMargin: margin)),
          );
      await tester.pumpWidget(editor(true));
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic', rows: 14);
      await tester.pump();
      await tester.runAsync(() => _until(() => c.imageCache!.peek('pic') != null));
      c.focusNode.requestFocus();
      c.selection = TextSelection.collapsed(offset: c.imageRunAt(6)!.start);
      await tester.pump();
      await tester.pump();
      int rows() => c.imageRunAt(6)!.rows;

      await tester.tap(find.text('Full'));
      await tester.pump();
      await tester.pump();
      final fullWithMargin = rows();

      await tester.pumpWidget(editor(false));
      await tester.pumpAndSettle();
      expect(rows(), greaterThan(fullWithMargin), reason: 'the wider column needs a taller (still full-width) picture');
      // And back: narrower column, shorter picture, no spare rows.
      await tester.pumpWidget(editor(true));
      await tester.pumpAndSettle();
      expect(rows(), fullWithMargin);

      // A picture sized smaller on purpose is not touched.
      await tester.tap(find.text('S'));
      await tester.pump();
      await tester.pump();
      final small = rows();
      await tester.pumpWidget(editor(false));
      await tester.pumpAndSettle();
      expect(rows(), small);
      expect(c.selection.isValid, isTrue);
    });

    testWidgets('a selected picture opens in the host viewer: by a tap on it, or the View button', (tester) async {
      final store = FakeStore()..files['pic'] = _png;
      final c = make('hello')..imageStore = store;
      addTearDown(c.dispose);
      final opened = <String>[];
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(body: RichTextEditor(controller: c, scrollController: ScrollController(), autofocus: false, onOpenImage: (run) => opened.add(run.id))),
      ));
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic', rows: 8);
      await tester.pump();
      await tester.runAsync(() => _until(() => c.imageCache!.peek('pic') != null));
      c.focusNode.requestFocus();
      c.selection = TextSelection.collapsed(offset: c.imageRunAt(6)!.start);
      await tester.pump();
      await tester.pump();

      expect(find.byTooltip('View picture'), findsOneWidget);
      await tester.tap(find.byTooltip('View picture'));
      expect(opened, ['pic']);

      final region = c.renderer.imageBlocks.single;
      final editable = tester.getTopLeft(find.byType(EditableText));
      await tester.tapAt(editable + Offset(60, region.top + 40));
      await tester.pump();
      expect(opened, ['pic', 'pic'], reason: 'a tap on the selected picture opens it');
    });

    testWidgets('selecting a picture far down scrolls it into view; a drag that starts on it still scrolls the note', (tester) async {
      final store = FakeStore()..files['pic'] = _png;
      final c = make('${List.generate(30, (i) => 'line $i').join('\n')}\n')..imageStore = store;
      addTearDown(c.dispose);
      final scroll = ScrollController();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 500);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(body: RichTextEditor(controller: c, scrollController: scroll, autofocus: false, onOpenImage: (_) {})),
      ));
      c.selection = TextSelection.collapsed(offset: c.text.length);
      c.insertImageBlock('pic', rows: 6);
      await tester.pump();
      await tester.runAsync(() => _until(() => c.imageCache!.peek('pic') != null));
      scroll.jumpTo(0);
      await tester.pump();
      expect(scroll.offset, 0);

      c.focusNode.requestFocus();
      c.selection = TextSelection.collapsed(offset: c.imageRunAt(c.text.length - 1)!.start);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      final region = c.renderer.imageBlocks.single;
      final top = 12 + region.top - scroll.offset;
      expect(scroll.offset, greaterThan(0), reason: 'scrolled down to the picture');
      expect(top, greaterThanOrEqualTo(0));
      expect(top + region.height, lessThanOrEqualTo(500), reason: 'the whole picture is on screen');

      // A drag that starts on the selected picture scrolls the note (the picture
      // does not take the touch away from the scrollable).
      final before = scroll.offset;
      await tester.dragFrom(Offset(150, top + region.height / 2), const Offset(0, 150));
      await tester.pump();
      expect(scroll.offset, lessThan(before), reason: 'dragging down on the picture scrolled up');
    });

    testWidgets('the grid stays whole: every line is one row high with a picture in the note', (tester) async {
      final (c, _) = await pumpEditor(tester);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.insertImageBlock('pic', rows: 6);
      await tester.pump();
      final bottoms = c.renderer.lineBottomOffsets(
        c.document,
        maxWidth: 300,
        style: const TextStyle(fontSize: 16),
        strutStyle: const StrutStyle(fontSize: 16, height: 1.9, forceStrutHeight: true),
      );
      for (var i = 1; i < bottoms.length; i++) {
        expect(bottoms[i] - bottoms[i - 1], closeTo(bottoms[0], 0.01), reason: 'line $i');
      }
    });

    testWidgets('a picture sent by the keyboard is accepted when there is a store', (tester) async {
      final (c, _) = await pumpEditor(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.contentInsertionConfiguration, isNotNull);
      expect(field.contentInsertionConfiguration!.allowedMimeTypes, contains('image/png'));
      c.imageStore = null;
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).contentInsertionConfiguration, isNull);
    });
  });
}
