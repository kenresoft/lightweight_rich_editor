import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';
import 'package:lightweight_rich_editor/src/rendering/text_span_renderer.dart';

void main() {
  group('TextSpanRenderer — basic rendering', () {
    test('an empty document renders a single empty span', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('');

      final span = renderer.renderSpan(document);

      expect(span.text, '');
      expect(span.children, isNull);
    });

    test('unformatted text with no composing region renders as one flat span', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello world');

      final span = renderer.renderSpan(document);

      expect(span.text, 'hello world');
      expect(span.children, isNull);
    });

    test('a bold span produces bold text in that range only', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'hello world',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.bold)],
      );

      final span = renderer.renderSpan(document);
      final children = span.children!.cast<TextSpan>();

      expect(children.first.text, 'hello');
      expect(children.first.style!.fontWeight, FontWeight.bold);
      expect(children.last.text, ' world');
      expect(children.last.style!.fontWeight, isNot(FontWeight.bold));
    });

    test('header attribute sets the theme h1 font size and bold weight', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'Title',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1')],
      );

      final span = renderer.renderSpan(document);
      final child = span.children!.cast<TextSpan>().single;

      expect(child.style!.fontSize, renderer.theme.h1FontSize);
      expect(child.style!.fontWeight, FontWeight.bold);
    });

    test('color attribute resolves to the exact ARGB color', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'red text',
        [const TextAttribute(start: 0, end: 3, type: AttributeType.color, value: 0xFFFF0000)],
      );

      final span = renderer.renderSpan(document);
      final first = span.children!.cast<TextSpan>().first;

      expect(first.style!.color, const Color(0xFFFF0000));
    });

    test('overlapping bold and italic both apply within their shared range', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'abcdef',
        [
          const TextAttribute(start: 0, end: 4, type: AttributeType.bold),
          const TextAttribute(start: 2, end: 6, type: AttributeType.italic),
        ],
      );

      final span = renderer.renderSpan(document);
      final children = span.children!.cast<TextSpan>();

      // Expect three segments: bold-only "ab", bold+italic "cd", italic-only "ef".
      expect(children.map((c) => c.text).toList(), ['ab', 'cd', 'ef']);
      expect(children[0].style!.fontWeight, FontWeight.bold);
      expect(children[0].style!.fontStyle, isNot(FontStyle.italic));
      expect(children[1].style!.fontWeight, FontWeight.bold);
      expect(children[1].style!.fontStyle, FontStyle.italic);
      expect(children[2].style!.fontWeight, isNot(FontWeight.bold));
      expect(children[2].style!.fontStyle, FontStyle.italic);
    });

    test('the IME composing range renders underlined even with no attributes', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('typing');

      final span = renderer.renderSpan(document, composingRange: const TextRange(start: 0, end: 6));
      final children = span.children!.cast<TextSpan>();

      expect(children.single.style!.decoration, TextDecoration.underline);
    });
  });

  group('TextSpanRenderer — caching', () {
    test('rendering the same document twice with the same inputs returns the identical span', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello');

      final first = renderer.renderSpan(document);
      final second = renderer.renderSpan(document);

      expect(identical(first, second), isTrue);
    });

    test('a text edit invalidates the cache', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello');

      final first = renderer.renderSpan(document);
      document.reset('hello world');
      final second = renderer.renderSpan(document);

      expect(identical(first, second), isFalse);
      expect(second.text, 'hello world');
    });

    test('an attribute-only change (same text) invalidates the cache via AttributeStore.revision', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello');

      final first = renderer.renderSpan(document);
      document.attributeStore.insert(const TextAttribute(start: 0, end: 5, type: AttributeType.bold));
      final second = renderer.renderSpan(document);

      expect(identical(first, second), isFalse);
      expect(second.children!.cast<TextSpan>().single.style!.fontWeight, FontWeight.bold);
    });

    test('a different base style invalidates the cache', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello');

      final first = renderer.renderSpan(document);
      final second = renderer.renderSpan(document, style: const TextStyle(fontSize: 20));

      expect(identical(first, second), isFalse);
    });
  });
}