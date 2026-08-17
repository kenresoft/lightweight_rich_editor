import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/models/paragraph_alignment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RichEditorController — TextField-driven editing (set value)', () {
    test('typing a character updates document text and selection', () {
      final controller = RichEditorController(text: 'hello');

      controller.value = const TextEditingValue(text: 'hello!', selection: TextSelection.collapsed(offset: 6));

      expect(controller.document.text, 'hello!');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
    });

    test('a selection-only change (no text change) does not touch the document', () {
      final controller = RichEditorController(text: 'hello');

      controller.value = const TextEditingValue(text: 'hello', selection: TextSelection.collapsed(offset: 2));

      expect(controller.document.text, 'hello');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    test('deleting via TextField (backspace) is recorded and undoable', () {
      final controller = RichEditorController(text: 'hello');
      controller.value = const TextEditingValue(text: 'hell', selection: TextSelection.collapsed(offset: 4));

      expect(controller.document.text, 'hell');
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.document.text, 'hello');
    });

    test('sequential TextField edits within the typing window coalesce into one undo step', () {
      final controller = RichEditorController(text: '');

      controller.value = const TextEditingValue(text: 'h', selection: TextSelection.collapsed(offset: 1));
      controller.value = const TextEditingValue(text: 'he', selection: TextSelection.collapsed(offset: 2));
      controller.value = const TextEditingValue(text: 'hey', selection: TextSelection.collapsed(offset: 3));

      expect(controller.document.text, 'hey');
      expect(controller.history.undoDepth, 1);

      controller.undo();
      expect(controller.document.text, '');
    });

    test('final selection matches what the TextField reported, not the diff math', () {
      // Autocorrect-style edit: text changes in the middle, but the
      // reported selection is somewhere the naive start+insertedLength
      // calculation wouldn't produce.
      final controller = RichEditorController(text: 'teh');

      controller.value = const TextEditingValue(
        text: 'the',
        selection: TextSelection.collapsed(offset: 0), // cursor jumped to the start
      );

      expect(controller.document.text, 'the');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    test('typing "# " converts the paragraph to an H1, consuming the marker', () {
      final controller = RichEditorController(text: '');
      controller.value = const TextEditingValue(text: '#', selection: TextSelection.collapsed(offset: 1));
      controller.value = const TextEditingValue(text: '# ', selection: TextSelection.collapsed(offset: 2));

      expect(controller.document.text, '');
      expect(controller.document.paragraphs.paragraphAt(0)!.headerLevel, 'h1');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    test('typing "## " converts the paragraph to an H2', () {
      final controller = RichEditorController(text: '');
      controller.value = const TextEditingValue(text: '#', selection: TextSelection.collapsed(offset: 1));
      controller.value = const TextEditingValue(text: '##', selection: TextSelection.collapsed(offset: 2));
      controller.value = const TextEditingValue(text: '## ', selection: TextSelection.collapsed(offset: 3));

      expect(controller.document.text, '');
      expect(controller.document.paragraphs.paragraphAt(0)!.headerLevel, 'h2');
    });

    test('undoing a "# " auto-format restores the marker text and header level in two steps', () {
      final controller = RichEditorController(text: '');
      controller.value = const TextEditingValue(text: '#', selection: TextSelection.collapsed(offset: 1));
      controller.value = const TextEditingValue(text: '# ', selection: TextSelection.collapsed(offset: 2));
      expect(controller.document.paragraphs.paragraphAt(0)!.headerLevel, 'h1');
      expect(controller.document.text, '');

      controller.undo(); // undoes SetHeaderLevelCommand — metadata only, text unaffected
      expect(controller.document.paragraphs.paragraphAt(0)!.headerLevel, isNull);
      expect(controller.document.text, '');

      controller.undo(); // undoes the ReplaceRangeCommand that stripped '#'
      expect(controller.document.text, '#');
    });

    test('a space typed after a non-shortcut "#" elsewhere in the line is ordinary text', () {
      final controller = RichEditorController(text: 'not a #heading');
      controller.value = const TextEditingValue(
        text: 'not a #heading ',
        selection: TextSelection.collapsed(offset: 16),
      );

      expect(controller.document.text, 'not a #heading ');
      expect(controller.document.paragraphs.paragraphAt(0)!.headerLevel, isNull);
    });

    // Regression/documentation test, not a feature under test: unlike
    // headers, list markers need zero special-casing in this live-typing
    // path at all. listPrefixLength/listTypeOfPrefix already derive
    // list-ness from literal text on every render
    // (TextSpanRenderer._containsListPrefix), and EditingEngine.enterKeyEdit
    // already continues a matched prefix on Enter — so typing '- '/'1. '/
    // '- [ ] ' already "just works" the instant the characters land in the
    // document, with no auto-format trigger needed. This test exists to
    // catch a future regression if that ever stops being true.
    test('typing "- " already renders as a list item with no auto-format code involved', () {
      final controller = RichEditorController(text: '');
      controller.value = const TextEditingValue(text: '-', selection: TextSelection.collapsed(offset: 1));
      controller.value = const TextEditingValue(text: '- ', selection: TextSelection.collapsed(offset: 2));
      controller.value = const TextEditingValue(text: '- item', selection: TextSelection.collapsed(offset: 6));

      // Still literal text — no stored list-type field exists to check.
      expect(controller.document.text, '- item');

      // Pressing Enter continues the list, exactly as it would for a
      // prefix that arrived via paste or initial load.
      controller.insertText('\n');
      expect(controller.document.text, '- item\n- ');
    });

    test('typing "1. " already renumbers a following item on Enter with no auto-format code involved', () {
      final controller = RichEditorController(text: '');
      controller.value = const TextEditingValue(text: '1', selection: TextSelection.collapsed(offset: 1));
      controller.value = const TextEditingValue(text: '1.', selection: TextSelection.collapsed(offset: 2));
      controller.value = const TextEditingValue(text: '1. ', selection: TextSelection.collapsed(offset: 3));
      controller.value = const TextEditingValue(text: '1. one', selection: TextSelection.collapsed(offset: 6));

      controller.insertText('\n');
      expect(controller.document.text, '1. one\n2. ');
    });
  });

  group('RichEditorController — programmatic editing API', () {
    test('insertText inserts and moves the caret to the correct position', () {
      final controller = RichEditorController(text: 'hello world');
      controller.value = controller.value.copyWith(selection: const TextSelection.collapsed(offset: 5));

      controller.insertText(',');

      expect(controller.document.text, 'hello, world');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
    });

    test('toggleBold on a selection is reflected by isAttributeActive', () {
      final controller = RichEditorController(text: 'hello world');
      controller.value = controller.value.copyWith(selection: const TextSelection(baseOffset: 0, extentOffset: 5));

      controller.toggleBold();

      expect(controller.isAttributeActive(AttributeType.bold), isTrue);
    });

    test('setHeader applies to the whole paragraph from a collapsed caret', () {
      final controller = RichEditorController(text: 'line one\nline two');
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 11), // inside "line two"
      );

      controller.setHeader('h1');

      // Header is ParagraphIndex-owned metadata, not an AttributeStore
      // span — see lib/ARCHITECTURE.md's "why headers are stored in
      // ParagraphIndex" section — so it's read from `paragraphs`, not
      // `attributeStore`.
      final paragraphs = controller.document.paragraphs;
      final lineTwoStart = 'line one\n'.length;
      expect(paragraphs.paragraphAt(lineTwoStart)!.headerLevel, 'h1');
      expect(paragraphs.paragraphAt(3)!.headerLevel, isNull); // "line one" untouched
    });

    test('setAlignment applies to the whole paragraph from a collapsed caret, and undoes', () {
      final controller = RichEditorController(text: 'line one\nline two');
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 11), // inside "line two"
      );

      controller.setAlignment(ParagraphAlignment.center);

      final paragraphs = controller.document.paragraphs;
      final lineTwoStart = 'line one\n'.length;
      expect(paragraphs.paragraphAt(lineTwoStart)!.alignment, ParagraphAlignment.center);
      expect(paragraphs.paragraphAt(3)!.alignment, isNull); // "line one" untouched
      expect(controller.activeAttributeValue(AttributeType.align), ParagraphAlignment.center);
      expect(controller.isAttributeActive(AttributeType.align), isTrue);

      controller.undo();
      expect(paragraphs.paragraphAt(lineTwoStart)!.alignment, isNull);
    });

    test('toggleTaskItem promotes a paragraph and isTaskChecked reflects it', () {
      final controller = RichEditorController(text: 'Buy milk');
      controller.value = controller.value.copyWith(selection: const TextSelection.collapsed(offset: 0));

      expect(controller.isTaskChecked(), isNull);
      controller.toggleTaskItem();
      expect(controller.document.text, '  - [ ] Buy milk');
      expect(controller.isTaskChecked(), isFalse);

      controller.toggleTaskItem();
      expect(controller.document.text, '  - [x] Buy milk');
      expect(controller.isTaskChecked(), isTrue);
    });

    test('formatting a selection does not change text length or selection', () {
      final controller = RichEditorController(text: 'hello world');
      const sel = TextSelection(baseOffset: 0, extentOffset: 5);
      controller.value = controller.value.copyWith(selection: sel);

      controller.toggleBold();

      expect(controller.document.text, 'hello world');
      expect(controller.selection, sel);
    });

    // The mechanism a toolbar popup relies on to keep formatting applying
    // to the text the user actually selected, even after the live
    // TextField selection has moved to the popup itself (e.g. tapping a
    // dropdown item steals focus) — see FormatToolbar's _HeaderMenu/
    // _ColorMenu, which call setSelectionHighlight(controller.selection)
    // on open specifically so this holds.
    test('setSelectionHighlight overrides which range programmatic formatting targets', () {
      final controller = RichEditorController(text: 'line one\nline two');
      // The "live" selection is inside "line one" ...
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 3),
      );
      // ... but a highlight preserves a different range, inside "line two",
      // simulating a popup menu having since stolen the live selection.
      final lineTwoStart = 'line one\n'.length;
      controller.setSelectionHighlight(TextRange(start: lineTwoStart, end: lineTwoStart + 4));

      controller.setHeader('h1');

      expect(controller.document.paragraphs.paragraphAt(lineTwoStart)!.headerLevel, 'h1');
      expect(controller.document.paragraphs.paragraphAt(3)!.headerLevel, isNull); // "line one" untouched
      expect(controller.activeAttributeValue(AttributeType.header), 'h1');

      controller.setSelectionHighlight(null);
      // Once cleared, formatting queries fall back to the live selection
      // again — still inside "line one", which was never given a header.
      expect(controller.activeAttributeValue(AttributeType.header), isNull);
    });

    test('calling an editing method before the field is ever focused does not crash', () {
      // Regression test: a fresh TextEditingController's selection is
      // (-1, -1) until something focuses it. Calling a programmatic
      // editing method in that state used to pass -1 straight through
      // to EditingEngine and trip its bounds assertion.
      final controller = RichEditorController(text: 'hello');
      expect(controller.selection.start, -1, reason: 'sanity check: this is the actual default Flutter gives us');

      controller.insertText('!');

      expect(controller.document.text, 'hello!');
    });
  });

  group('RichEditorController — undo/redo', () {
    test('canUndo/canRedo reflect controller state', () {
      final controller = RichEditorController(text: 'hi');
      controller.value = controller.value.copyWith(selection: const TextSelection.collapsed(offset: 2));
      expect(controller.canUndo, isFalse);

      controller.insertText('!');
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);

      controller.undo();
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.document.text, 'hi!');
    });
  });

  group('RichEditorController — notification on formatting-only changes', () {
    // Regression coverage for a real bug: TextEditingController's
    // inherited value setter skips notifyListeners() when the new
    // TextEditingValue equals the old one, but TextEditingValue has no
    // concept of formatting — a pure attribute change leaves
    // text/selection/composing all identical, so without _applyValue's
    // explicit force-notify, a bold toggle would apply to the document
    // but never trigger a TextField rebuild.
    test('toggling bold fires a listener even though text and selection are unchanged', () {
      final controller = RichEditorController(text: 'hello world');
      controller.value = controller.value.copyWith(selection: const TextSelection(baseOffset: 0, extentOffset: 5));

      var notified = false;
      controller.addListener(() => notified = true);

      controller.toggleBold();

      expect(notified, isTrue);
      expect(controller.isAttributeActive(AttributeType.bold), isTrue);
    });

    test('undoing a formatting-only command fires a listener', () {
      final controller = RichEditorController(text: 'hello world');
      controller.value = controller.value.copyWith(selection: const TextSelection(baseOffset: 0, extentOffset: 5));
      controller.toggleBold();

      var notified = false;
      controller.addListener(() => notified = true);

      controller.undo();

      expect(notified, isTrue);
      expect(controller.isAttributeActive(AttributeType.bold), isFalse);
    });

    test('setHeader on a collapsed caret (text/selection unchanged) fires a listener', () {
      final controller = RichEditorController(text: 'a line of text');
      controller.value = controller.value.copyWith(selection: const TextSelection.collapsed(offset: 3));

      var notified = false;
      controller.addListener(() => notified = true);

      controller.setHeader('h1');

      expect(notified, isTrue);
    });
  });

  group('RichEditorController — rendered span integrity', () {
    testWidgets('buildTextSpan never produces a span whose length disagrees with the document', (tester) async {
      final controller = RichEditorController(
        text: 'hello world',
        initialAttributes: const [TextAttribute(start: 0, end: 5, type: AttributeType.bold)],
      );

      late BuildContext capturedContext;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      );

      // The assertion inside buildTextSpan itself is the real check here
      // — it throws in debug mode if TextSpanRenderer ever produces a
      // mismatched length. A clean call is a pass.
      expect(() => controller.buildTextSpan(context: capturedContext, withComposing: false), returnsNormally);
    });
  });

  group('RichEditorController — search-driven rendering', () {
    testWidgets('buildTextSpan highlights the current search match', (tester) async {
      final controller = RichEditorController(text: 'find the needle here');
      late BuildContext capturedContext;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      );

      controller.find('needle');
      final span = controller.buildTextSpan(context: capturedContext, withComposing: false);
      final matchSegment = span.children!.cast<TextSpan>().firstWhere((c) => c.text == 'needle');

      expect(matchSegment.style!.backgroundColor, controller.renderer.theme.matchHighlightColor);
    });

    testWidgets('buildTextSpan highlights every other match with otherMatchesHighlightColor', (tester) async {
      final controller = RichEditorController(text: 'cat cat cat');
      late BuildContext capturedContext;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      );

      controller.find('cat');
      final span = controller.buildTextSpan(context: capturedContext, withComposing: false);
      final matches = span.children!.cast<TextSpan>().where((c) => c.text == 'cat').toList();

      expect(matches.length, 3);
      expect(matches.first.style!.backgroundColor, controller.renderer.theme.matchHighlightColor);
      for (final other in matches.skip(1)) {
        expect(other.style!.backgroundColor, controller.renderer.theme.otherMatchesHighlightColor);
      }
    });

    test('a query with no results still notifies (clears any stale highlight)', () {
      // Regression test: searching for something with zero matches used
      // to skip notifyListeners entirely, which meant a *previous*
      // search's highlighted match stayed stuck on screen after the new,
      // empty search.
      final controller = RichEditorController(text: 'hello world');
      var notified = false;
      controller.addListener(() => notified = true);

      controller.find('xyz');

      expect(notified, isTrue);
      expect(controller.search.currentMatch, isNull);
    });

    test('clearFind notifies even though value itself is unchanged', () {
      final controller = RichEditorController(text: 'hello world');
      controller.find('world');
      var notified = false;
      controller.addListener(() => notified = true);

      controller.clearFind();

      expect(notified, isTrue);
      expect(controller.search.currentMatch, isNull);
    });
  });

  group('RichEditorController — document load', () {
    test('loadDocument replaces content and clears history', () {
      final controller = RichEditorController(text: 'old note');
      controller.value = controller.value.copyWith(selection: const TextSelection.collapsed(offset: 8));
      controller.insertText('!');
      expect(controller.canUndo, isTrue);

      controller.loadDocument('a different note');

      expect(controller.document.text, 'a different note');
      expect(controller.canUndo, isFalse);
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });
  });

  group('RichEditorController — sticky attributes do not leak past a range apply', () {
    // Regression test for a real, reported bug: applying an attribute
    // with a *value* (link) to a real selection used to also stash that
    // value in EditingEngine's sticky-attributes map, on the theory that
    // it mirrored "keep bolding as you keep typing right after a bolded
    // selection". Nothing ever cleared it for a *non-collapsed* future
    // selection change (syncStickyAttributesAt only runs when the new
    // selection is collapsed) — so "select all" followed by any insertion
    // (a plain-text paste, most visibly) picked the stale sticky link
    // back up and applied the *previous* note's URL to text that has
    // nothing to do with it.
    test('linkifying a URL, then select-all + paste plain text, does not linkify the pasted text', () {
      const url = 'https://example.com';
      final controller = RichEditorController(text: url);
      controller.value = controller.value.copyWith(
        selection: TextSelection(baseOffset: 0, extentOffset: url.length),
      );

      controller.setLink(url);
      expect(controller.document.attributes.any((a) => a.type == AttributeType.link), isTrue);

      // Select all, then paste plain text over it — the pasted text
      // shares nothing with the link that used to be there.
      controller.value = controller.value.copyWith(
        selection: TextSelection(baseOffset: 0, extentOffset: url.length),
      );
      controller.pasteText('just some plain text');

      expect(controller.document.text, 'just some plain text');
      expect(controller.document.attributes.any((a) => a.type == AttributeType.link), isFalse);
    });

    test('bolding a selection, then select-all + paste plain text, does not bold the pasted text', () {
      final controller = RichEditorController(text: 'hello world');
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 11),
      );

      controller.toggleBold();
      expect(controller.document.attributes.any((a) => a.type == AttributeType.bold), isTrue);

      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 11),
      );
      controller.pasteText('fresh text');

      expect(controller.document.text, 'fresh text');
      expect(controller.document.attributes.any((a) => a.type == AttributeType.bold), isFalse);
    });
  });

  group('RichEditorController.pasteText — autolinking', () {
    // Regression test for a real, reported bug: only `paste()` (the
    // async, system-clipboard path via ClipboardManager) ran autolink
    // detection over pasted text. `pasteText` — the direct, synchronous
    // "insert this plain text" API a host might use for drag-and-drop, a
    // share-sheet handoff, or its own "insert" action — never did,
    // leaving a pasted bare URL sitting unlinked until the user
    // separately typed a boundary character right after it.
    test('a bare URL pasted via pasteText is linkified immediately, with no trailing keystroke needed', () {
      final controller = RichEditorController();
      controller.pasteText('visit https://example.com today');

      final link = controller.document.attributes.singleWhere((a) => a.type == AttributeType.link);
      expect(controller.document.text.substring(link.start, link.end), 'https://example.com');
      expect(link.value, 'https://example.com');
    });

    test('pasted text with no URL is unaffected', () {
      final controller = RichEditorController();
      controller.pasteText('just some plain text');

      expect(controller.document.text, 'just some plain text');
      expect(controller.document.attributes, isEmpty);
    });

    test('the non-URL portion of the pasted text still inherits active sticky formatting', () {
      final controller = RichEditorController(text: 'x');
      controller.value = controller.value.copyWith(selection: const TextSelection.collapsed(offset: 1));
      controller.toggleBold();

      controller.pasteText('visit https://example.com today');

      final bold = controller.document.attributes.singleWhere((a) => a.type == AttributeType.bold);
      expect(controller.document.text.substring(bold.start, bold.end), 'visit https://example.com today');
      final link = controller.document.attributes.singleWhere((a) => a.type == AttributeType.link);
      expect(controller.document.text.substring(link.start, link.end), 'https://example.com');
    });

    // Regression test for a real, reported bug: pasting multi-line text
    // with '\r\n' line endings (e.g. from Windows drag-and-drop or a
    // share-sheet handoff -- exactly the sources this method's own doc
    // comment names) failed to linkify affected URLs, and left stray
    // '\r' characters embedded in the document text besides. See
    // ClipboardManager.paste's matching fix for the full root-cause
    // explanation (an un-normalized '\r' isn't a recognized autolink
    // boundary, so it gets folded into the URL token and defeats the
    // trailing-punctuation trim too).
    test('URLs in \\r\\n-delimited pasted text are linkified, and no \\r survives in the document', () {
      final controller = RichEditorController();
      controller.pasteText(
        'Production Apps:\r\n'
        'https://play.google.com/store/apps/details?id=com.phunplan.phunplan, \r\n'
        'https://apps.apple.com/app/6763565579,\r\n'
        'https://play.google.com/store/apps/details?id=com.telomii.telomii,\r\n'
        'https://play.google.com/store/apps/details?id=com.lfb.desktopbrowser',
      );

      final links = controller.document.attributes.where((a) => a.type == AttributeType.link).toList();
      expect(links, hasLength(4));
      expect(links[0].value, 'https://play.google.com/store/apps/details?id=com.phunplan.phunplan');
      expect(links[1].value, 'https://apps.apple.com/app/6763565579');
      expect(links[2].value, 'https://play.google.com/store/apps/details?id=com.telomii.telomii');
      expect(links[3].value, 'https://play.google.com/store/apps/details?id=com.lfb.desktopbrowser');
      expect(controller.document.text.contains('\r'), isFalse);
    });
  });
}
