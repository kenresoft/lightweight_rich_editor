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

    test('a header line height is quantized to a whole multiple of theme.lineHeight, not squashed to one row', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'Title',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1')],
      );

      final span = renderer.renderSpan(document);
      final child = span.children!.cast<TextSpan>().single;
      final lineHeight = renderer.theme.lineHeight;
      final resolvedPx = child.style!.height! * child.style!.fontSize!;

      // A whole number of rows, not a fractional one -- this is what
      // keeps ruled lines below a header from drifting off the grid.
      expect(resolvedPx % lineHeight, closeTo(0, 0.001));
      // At the default theme (h1FontSize 28 vs lineHeight 24), one row
      // isn't enough -- this must have grown to at least 2.
      expect(resolvedPx, greaterThanOrEqualTo(lineHeight * 2));
    });

    test('plain body text still resolves to exactly one row', () {
      // A bare `renderSpan(EditorDocument.fromText('hello world'))` takes
      // the flat-span fast path (no children, so no resolved TextStyle
      // to inspect) -- an attributed span forces the full resolution
      // path instead, giving us a concrete style to check the height on.
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'hello world',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.bold)],
      );

      final span = renderer.renderSpan(document);
      final child = span.children!.cast<TextSpan>().first;
      final resolvedPx = child.style!.height! * child.style!.fontSize!;

      expect(resolvedPx, closeTo(renderer.theme.lineHeight, 0.001));
    });

    test('a header line still fits within its quantized height in TextPainter.computeLineMetrics', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'Title',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1')],
      );

      final bottoms = renderer.lineBottomOffsets(
        document,
        maxWidth: 400,
        strutStyle: StrutStyle(
          fontSize: renderer.theme.baseFontSize,
          height: renderer.theme.lineHeight / renderer.theme.baseFontSize,
          leading: 0.0,
        ),
      );

      expect(bottoms.single % renderer.theme.lineHeight, closeTo(0, 0.001));
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

  group('TextSpanRenderer — all-matches highlight', () {
    test('paints every range in allMatchesRanges with otherMatchesHighlightColor', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('cat cat cat');

      final span = renderer.renderSpan(
        document,
        allMatchesRanges: const [
          TextRange(start: 0, end: 3),
          TextRange(start: 4, end: 7),
          TextRange(start: 8, end: 11),
        ],
      );
      final children = span.children!.cast<TextSpan>();

      expect(children.length, greaterThanOrEqualTo(3));
      for (final child in children.where((c) => c.text == 'cat')) {
        expect(child.style!.backgroundColor, renderer.theme.otherMatchesHighlightColor);
      }
    });

    test('the current match keeps matchHighlightColor even when it also appears in allMatchesRanges', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('cat cat cat');

      final span = renderer.renderSpan(
        document,
        matchHighlightRange: const TextRange(start: 0, end: 3),
        allMatchesRanges: const [
          TextRange(start: 0, end: 3),
          TextRange(start: 4, end: 7),
          TextRange(start: 8, end: 11),
        ],
      );
      final children = span.children!.cast<TextSpan>();

      final current = children.first;
      expect(current.text, 'cat');
      expect(current.style!.backgroundColor, renderer.theme.matchHighlightColor);

      final others = children.where((c) => c.text == 'cat').skip(1);
      for (final child in others) {
        expect(child.style!.backgroundColor, renderer.theme.otherMatchesHighlightColor);
      }
    });

    test('an identical list instance is a cache hit', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('cat cat cat');
      const ranges = [TextRange(start: 0, end: 3), TextRange(start: 4, end: 7)];

      final first = renderer.renderSpan(document, allMatchesRanges: ranges);
      final second = renderer.renderSpan(document, allMatchesRanges: ranges);

      expect(identical(first, second), isTrue);
    });

    test('a different list instance invalidates the cache, even with equal contents', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('cat cat cat');

      final first = renderer.renderSpan(
        document,
        allMatchesRanges: List.of([const TextRange(start: 0, end: 3)]),
      );
      final second = renderer.renderSpan(
        document,
        allMatchesRanges: List.of([const TextRange(start: 0, end: 3)]),
      );

      expect(identical(first, second), isFalse);
    });

    test('an empty list behaves the same as omitting it entirely', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('plain text');

      final withEmpty = renderer.renderSpan(document, allMatchesRanges: const []);

      expect(withEmpty.text, 'plain text');
      expect(withEmpty.children, isNull);
    });
  });

  group('TextSpanRenderer — horizontal rules', () {
    test('a line of three hyphens renders with the marker color', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('---');

      final span = renderer.renderSpan(document);
      final child = span.children!.cast<TextSpan>().single;

      expect(child.text, '---');
      expect(child.style!.color, renderer.theme.listMarkerColor);
      expect(child.style!.letterSpacing, 3.0);
    });

    test('a longer run of hyphens also renders as a rule', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('----------');

      final span = renderer.renderSpan(document);
      final child = span.children!.cast<TextSpan>().single;

      expect(child.text, '----------');
      expect(child.style!.color, renderer.theme.listMarkerColor);
    });

    test('two hyphens do not render as a rule', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('--');

      final span = renderer.renderSpan(document);

      expect(span.text, '--');
      expect(span.children, isNull);
    });

    test('hyphens followed by other text on the same line do not render as a rule', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('---not a rule');

      final span = renderer.renderSpan(document);

      expect(span.text, '---not a rule');
      expect(span.children, isNull);
    });

    test('a horizontal rule paragraph among other paragraphs only styles its own line', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('above\n---\nbelow');

      final span = renderer.renderSpan(document);
      final children = span.children!.cast<TextSpan>();

      expect(children.map((c) => c.text).toList(), ['above\n', '---\n', 'below']);
      expect(children[0].style!.color, isNot(renderer.theme.listMarkerColor));
      expect(children[1].style!.color, renderer.theme.listMarkerColor);
      expect(children[2].style!.color, isNot(renderer.theme.listMarkerColor));
    });

    test('a bullet marker is unaffected by horizontal rule detection', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('- Item');

      final span = renderer.renderSpan(document);
      final children = span.children!.cast<TextSpan>();

      expect(children.first.text, '- ');
      expect(children.first.style!.fontWeight, FontWeight.w600);
      expect(children.first.style!.letterSpacing, isNot(3.0));
    });
  });

  group('TextSpanRenderer — lineBottomOffsets', () {
    const strut = StrutStyle(fontSize: 16, height: 24 / 16, leading: 0.0);
    const style = TextStyle(fontSize: 16, height: 24 / 16);

    test('a single short line produces exactly one entry', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello');

      final bottoms = renderer.lineBottomOffsets(
        document,
        maxWidth: 400,
        style: style,
        strutStyle: strut,
      );

      expect(bottoms.length, 1);
      expect(bottoms.single, greaterThan(0));
    });

    test('two paragraphs produce two increasing entries', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('first\nsecond');

      final bottoms = renderer.lineBottomOffsets(
        document,
        maxWidth: 400,
        style: style,
        strutStyle: strut,
      );

      expect(bottoms.length, 2);
      expect(bottoms[1], greaterThan(bottoms[0]));
    });

    test('a narrow width wraps a single paragraph into multiple lines', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('a fairly long line of plain text that must wrap');

      final wide = renderer.lineBottomOffsets(document, maxWidth: 2000, style: style, strutStyle: strut);
      final narrow = renderer.lineBottomOffsets(document, maxWidth: 60, style: style, strutStyle: strut);

      expect(wide.length, 1);
      expect(narrow.length, greaterThan(1));
    });

    test('a cache hit returns the identical list instance', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello world');

      final first = renderer.lineBottomOffsets(document, maxWidth: 400, style: style, strutStyle: strut);
      final second = renderer.lineBottomOffsets(document, maxWidth: 400, style: style, strutStyle: strut);

      expect(identical(first, second), isTrue);
    });

    test('a changed maxWidth invalidates the cache', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText('hello world');

      final first = renderer.lineBottomOffsets(document, maxWidth: 400, style: style, strutStyle: strut);
      final second = renderer.lineBottomOffsets(document, maxWidth: 100, style: style, strutStyle: strut);

      expect(identical(first, second), isFalse);
    });

    test('a text edit invalidates the cache', () {
      final renderer = TextSpanRenderer();
      final before = EditorDocument.fromText('hello');
      final after = EditorDocument.fromText('hello world');

      final first = renderer.lineBottomOffsets(before, maxWidth: 400, style: style, strutStyle: strut);
      final second = renderer.lineBottomOffsets(after, maxWidth: 400, style: style, strutStyle: strut);

      expect(identical(first, second), isFalse);
    });

    test('a header paragraph does not throw and stays internally consistent', () {
      final renderer = TextSpanRenderer();
      final document = EditorDocument.fromText(
        'Title\nbody text',
        [const TextAttribute(start: 0, end: 5, type: AttributeType.header, value: 'h1')],
      );

      final bottoms = renderer.lineBottomOffsets(document, maxWidth: 400, style: style, strutStyle: strut);

      expect(bottoms.length, 2);
      expect(bottoms[1], greaterThan(bottoms[0]));
    });
  });
}