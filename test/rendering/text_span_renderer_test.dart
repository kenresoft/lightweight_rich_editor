import 'package:flutter/gestures.dart';
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

  group('TextSpanRenderer — link taps', () {
    test('a link segment gets no recognizer when onTapLink is not set', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'click here',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.link, value: 'https://example.com')],
      );

      final span = renderer.renderSpan(document);
      expect(span.children!.cast<TextSpan>().first.recognizer, isNull);
    });

    test('tapping a link segment invokes onTapLink with its URL', () {
      String? tappedUrl;
      final renderer = TextSpanRenderer(onTapLink: (url) => tappedUrl = url);
      final document = EditorDocument.fromText(
        'click here',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.link, value: 'https://example.com')],
      );

      final span = renderer.renderSpan(document);
      final recognizer = span.children!.cast<TextSpan>().first.recognizer as TapGestureRecognizer;
      recognizer.onTap!();

      expect(tappedUrl, 'https://example.com');
    });

    test('rebuilding after a text edit produces a fresh recognizer for the new span', () {
      final renderer = TextSpanRenderer(onTapLink: (_) {});
      final document = EditorDocument.fromText(
        'click here',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.link, value: 'https://example.com')],
      );

      final first = renderer.renderSpan(document);
      final firstRecognizer = first.children!.cast<TextSpan>().first.recognizer;

      document.reset(
        'click there',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.link, value: 'https://example.com')],
      );
      final second = renderer.renderSpan(document);
      final secondRecognizer = second.children!.cast<TextSpan>().first.recognizer;

      // Not the same object — the old one should have been disposed
      // (renderer.dispose(), tested below, is the safety net if it
      // wasn't), not reused across a rebuild.
      expect(identical(firstRecognizer, secondRecognizer), isFalse);
    });

    test('renderer.dispose() does not throw, including with no prior renders', () {
      expect(() => TextSpanRenderer(onTapLink: (_) {}).dispose(), returnsNormally);
    });

    test('renderer.dispose() after rendering link content does not throw', () {
      final renderer = TextSpanRenderer(onTapLink: (_) {});
      final document = EditorDocument.fromText(
        'click here',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.link, value: 'https://example.com')],
      );
      renderer.renderSpan(document);

      expect(() => renderer.dispose(), returnsNormally);
    });
  });

  group('TextSpanRenderer — match highlight', () {
    test('paints matchHighlightRange with the theme\'s matchHighlightColor', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('find the needle here');

      final span = renderer.renderSpan(
        document,
        matchHighlightRange: const TextRange(start: 9, end: 15), // "needle"
      );
      final children = span.children!.cast<TextSpan>();

      final matchSegment = children.firstWhere((c) => c.text == 'needle');
      expect(matchSegment.style!.backgroundColor, renderer.theme.matchHighlightColor);
    });

    test('match highlight takes priority over the highlight attribute', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'needle',
        [const TextAttribute(start: 0, end: 6, type: AttributeType.highlight)],
      );

      final span = renderer.renderSpan(document, matchHighlightRange: const TextRange(start: 0, end: 6));

      expect(span.children!.cast<TextSpan>().single.style!.backgroundColor, renderer.theme.matchHighlightColor);
    });

    test('text outside the match range is unaffected', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('needle in a haystack');

      final span = renderer.renderSpan(document, matchHighlightRange: const TextRange(start: 0, end: 6));
      final children = span.children!.cast<TextSpan>();

      final outside = children.firstWhere((c) => c.text == ' in a haystack');
      expect(outside.style!.backgroundColor, isNot(renderer.theme.matchHighlightColor));
    });

    test('a changed matchHighlightRange invalidates the cache', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('cat cat cat');

      final first = renderer.renderSpan(document, matchHighlightRange: const TextRange(start: 0, end: 3));
      final second = renderer.renderSpan(document, matchHighlightRange: const TextRange(start: 4, end: 7));

      expect(identical(first, second), isFalse);
    });

    test('the same matchHighlightRange across calls is a cache hit', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('cat cat cat');
      const range = TextRange(start: 0, end: 3);

      final first = renderer.renderSpan(document, matchHighlightRange: range);
      final second = renderer.renderSpan(document, matchHighlightRange: range);

      expect(identical(first, second), isTrue);
    });
  });
}