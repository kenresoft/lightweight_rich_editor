// Pictures arriving through an import (pasted web page / Markdown) or by address.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/images/image_source.dart';
import 'package:lightweight_rich_editor/src/import/html_importer.dart';
import 'package:lightweight_rich_editor/src/import/markdown_importer.dart';

import '../support/notebook_test_support.dart';

// A 1x1 PNG.
const _pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const _dataUri = 'data:image/png;base64,$_pngBase64';

class _Store extends RichImageStore {
  final Map<String, Uint8List> files = {};
  int _n = 0;

  @override
  Future<String> save(Uint8List bytes) async {
    final id = 'img${++_n}';
    files[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> load(String id) async => files[id];
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HTML', () {
    test('an <img> becomes a placeholder block between its paragraphs, and is listed', () {
      final r = const HtmlImporter().parse('<p>before</p><p><img src="https://example.com/a.png" width="600" height="300" alt="A cat"></p><p>after</p>', images: true);
      expect(r.images, hasLength(1));
      expect(r.images.single.source, 'https://example.com/a.png');
      expect(r.images.single.alt, 'A cat');
      final level = r.images.single.level;
      expect(isImageLevel(level), isTrue);
      expect(imageIdOf(level), pendingImageId);
      final c = RichEditorController(text: r.text, initialAttributes: r.attributes);
      addTearDown(c.dispose);
      final run = c.imageRunByLevel(level)!;
      expect(c.text.substring(0, run.start), startsWith('before'));
      expect(c.text.substring(run.end), endsWith('after'));
    });

    test('without the images flag (no store) an <img> is ignored as before', () {
      final r = const HtmlImporter().parse('<p>x</p><img src="https://example.com/a.png"><p>y</p>');
      expect(r.images, isEmpty);
      expect(r.text, 'x\n\ny');
    });

    test('icons, emoji, tracking pixels, and non-web sources are not pictures', () {
      const html = '<img src="https://e.com/i.png" width="16" height="16">'
          '<img class="emoji" src="https://e.com/e.png">'
          '<img src="file:///sdcard/x.png">'
          '<img src="content://media/1">'
          '<img src="">'
          '<img>';
      expect(const HtmlImporter().parse(html, images: true).images, isEmpty);
    });

    test('a data: URI is accepted, and no more than the cap is taken from a long page', () {
      final many = List.generate(30, (i) => '<p><img src="https://e.com/$i.png" width="400" height="300"></p>').join();
      expect(const HtmlImporter().parse(many, images: true).images, hasLength(maxImportedImages));
      expect(const HtmlImporter().parse('<img src="$_dataUri">', images: true).images, hasLength(1));
    });
  });

  group('Markdown', () {
    test('a line of its own ![alt](url) is a picture; inline it is a link named by the alt text', () {
      final r = const MarkdownImporter().parse('Intro\n\n![Logo](https://e.com/logo.png "Title")\n\nText ![inline](https://e.com/b.png) end', images: true);
      expect(r.images, hasLength(1));
      expect(r.images.single.source, 'https://e.com/logo.png');
      expect(r.images.single.alt, 'Logo');
      expect(r.text, contains('Text inline end'), reason: 'no stray "!"');
      expect(r.attributes.any((a) => a.type == AttributeType.link && a.value == 'https://e.com/b.png'), isTrue);
    });

    test('with images off, a picture line stays readable text', () {
      final r = const MarkdownImporter().parse('![Logo](https://e.com/logo.png)');
      expect(r.images, isEmpty);
      expect(r.text, contains('Logo'));
    });
  });

  group('source', () {
    test('data: URIs decode; other schemes, local hosts and junk are refused', () async {
      expect((await loadImageSource(_dataUri))!.length, base64Decode(_pngBase64).length);
      expect(await loadImageSource('file:///etc/passwd'), isNull);
      expect(await loadImageSource('ftp://example.com/a.png'), isNull);
      expect(await loadImageSource('http://localhost/a.png'), isNull);
      expect(await loadImageSource('https://192.168.1.10/a.png'), isNull);
      expect(await loadImageSource('https://10.0.0.5/a.png'), isNull);
      expect(await loadImageSource('data:image/png;base64,@@@'), isNull);
      expect(await loadImageSource('not a url'), isNull);
    });
  });

  group('filling placeholders in', () {
    test('a pasted page picture is fetched, stored and shown in place as one undo step; a failed one leaves no block', () async {
      final store = _Store();
      final c = RichEditorController(text: '', theme: notebookTheme)..imageStore = store;
      addTearDown(c.dispose);
      final r = const HtmlImporter().parse('<p>top</p><p><img src="$_dataUri" width="400" height="400"></p><p><img src="data:image/png;base64,AAAA"></p><p>bottom</p>', images: true);
      c.pasteRichText(r.text, r.attributes);
      expect(c.imageRunByLevel(r.images[0].level), isNotNull, reason: 'placeholder is there at once');
      expect(c.imageRunByLevel(r.images[1].level), isNotNull);

      await c.resolveImportedImages(r.images);

      expect(c.imageRunByLevel(r.images[0].level), isNull, reason: 'the pending level was replaced by the stored id');
      final shown = c.document.paragraphs.records.where((x) => isImageLevel(x.headerLevel)).toList();
      expect(shown, isNotEmpty);
      expect(imageIdOf(shown.first.headerLevel), 'img1');
      expect(store.files, hasLength(1), reason: 'only the real picture was stored');
      expect(shown.every((x) => imageIdOf(x.headerLevel) == 'img1'), isTrue, reason: 'the broken one is gone, not left blank');
      expect(c.text.startsWith('top'), isTrue);
      expect(c.text.endsWith('bottom'), isTrue);

      c.commands.undo(); // fill-in of the picture goes back to the placeholder (one step)
      expect(c.document.paragraphs.records.where((x) => imageIdOf(x.headerLevel) == 'img1'), isEmpty);
    });

    test('a placeholder deleted before its picture arrives is not resurrected, and disposal is safe', () async {
      final store = _Store();
      final c = RichEditorController(text: '', theme: notebookTheme)..imageStore = store;
      final r = const HtmlImporter().parse('<p>a</p><img src="$_dataUri" width="400" height="400"><p>b</p>', images: true);
      c.pasteRichText(r.text, r.attributes);
      c.deleteImage(c.imageRunByLevel(r.images.single.level)!);
      await c.resolveImportedImages(r.images);
      expect(c.document.paragraphs.records.where((x) => isImageLevel(x.headerLevel)), isEmpty);

      final c2 = RichEditorController(text: '', theme: notebookTheme)..imageStore = _Store();
      final r2 = const HtmlImporter().parse('<img src="$_dataUri" width="400" height="400">', images: true);
      c2.pasteRichText(r2.text, r2.attributes);
      final pending = c2.resolveImportedImages(r2.images);
      c2.dispose();
      await pending;
      c.dispose();
    });

    test('insertImageFromSource stores the picture and inserts it; bad sources return false', () async {
      final store = _Store();
      final c = RichEditorController(text: 'hi', theme: notebookTheme)..imageStore = store;
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 2);
      expect(await c.insertImageFromSource(_dataUri), isTrue);
      expect(c.document.paragraphs.records.any((x) => isImageLevel(x.headerLevel)), isTrue);
      expect(await c.insertImageFromSource('https://127.0.0.1/x.png'), isFalse);
      expect(await RichEditorController(text: '').insertImageFromSource(_dataUri), isFalse, reason: 'no store');
    });
  });
}

