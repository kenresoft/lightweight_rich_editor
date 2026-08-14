// Tests for EditingEngine's list-related structural edits: toggle,
// indent/outdent, backspace/forward-delete marker removal, Enter-driven
// renumbering, and clear-formatting. Written specifically to catch the
// two most recently found bugs — a link on one word spreading across
// an entire paragraph, and a crash when backspacing an empty list item
// mid-list — so they can never silently regress. Every expected value
// below was hand-traced against the actual method logic before being
// written here, not assumed.

import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_selection.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/models/paragraph_alignment.dart';
import 'package:lightweight_rich_editor/src/models/paragraph_text_direction.dart';
import 'package:lightweight_rich_editor/src/utils/list_prefix.dart';

EditingEngine _engineFor(String text, [List<TextAttribute> attributes = const []]) {
  final document = EditorDocument.fromText(text, attributes);
  final transactions = TransactionManager(() {});
  return EditingEngine(document: document, transactions: transactions);
}

/// Applies a computed edit exactly the way CommandDispatcher does in
/// production — via pasteRich, so these tests verify attributes
/// actually survive real application, not just that the computed edit
/// object happens to contain them.
void _apply(
    EditingEngine engine,
    ({int start, int end, String text, List<TextAttribute> relativeAttributes}) edit,
    ) {
  engine.pasteRich(
    EditorSelection(baseOffset: edit.start, extentOffset: edit.end),
    edit.text,
    edit.relativeAttributes,
  );
}

/// Same as [_apply], for the return shape `deleteBackwardEdit` and
/// `enterKeyEditWithRenumber` share (both also carry
/// `cursorOffsetFromStart`). Dart record types must match their field
/// set exactly, not just be a compatible subset — a 5-field record
/// isn't assignable where a 4-field one is expected, even when 4 of the
/// 5 fields line up — so this needs its own helper rather than reusing
/// [_apply] for both shapes.
void _applyWithCursor(
    EditingEngine engine,
    ({int start, int end, String text, int cursorOffsetFromStart, List<TextAttribute> relativeAttributes}) edit,
    ) {
  engine.pasteRich(
    EditorSelection(baseOffset: edit.start, extentOffset: edit.end),
    edit.text,
    edit.relativeAttributes,
  );
}

void main() {
  group('listToggleEdit — bullet', () {
    test('turning on inserts default 2-space indent + dash', () {
      final engine = _engineFor('Item one');
      final edit = engine.listToggleEdit(EditorSelection.collapsed(0), ParagraphListType.bullet);
      expect(edit, isNotNull);
      expect(edit!.text, '  - Item one');
    });

    test('turning off strips the marker', () {
      final engine = _engineFor('  - Item one');
      final edit = engine.listToggleEdit(EditorSelection.collapsed(0), ParagraphListType.bullet);
      expect(edit, isNotNull);
      expect(edit!.text, 'Item one');
    });

    test('preserves an inline attribute, shifted to match the new marker length', () {
      // "Item one" — "one" (positions 5-8) is bold.
      final engine = _engineFor('Item one', [
        TextAttribute(start: 5, end: 8, type: AttributeType.bold),
      ]);
      final edit = engine.listToggleEdit(EditorSelection.collapsed(0), ParagraphListType.bullet);
      expect(edit, isNotNull);
      expect(edit!.text, '  - Item one');
      // '  - ' is 4 chars, so bold shifts from [5,8) to [9,12).
      expect(edit.relativeAttributes, hasLength(1));
      expect(edit.relativeAttributes.first.type, AttributeType.bold);
      expect(edit.relativeAttributes.first.start, 9);
      expect(edit.relativeAttributes.first.end, 12);
    });
  });

  group('listToggleEdit — numbered, reproduces the reported link-propagation bug', () {
    test('toggling a paragraph with a mid-word link to numbered preserves the link range only', () {
      const text = 'This is a paragraph containing a linked word somewhere in the middle.';
      final linkStart = text.indexOf('linked word');
      final linkEnd = linkStart + 'linked word'.length;
      final engine = _engineFor(text, [
        TextAttribute(start: linkStart, end: linkEnd, type: AttributeType.link, value: 'https://example.com'),
      ]);

      final edit = engine.listToggleEdit(EditorSelection.collapsed(0), ParagraphListType.numbered);
      expect(edit, isNotNull);
      expect(edit!.text, '  1. $text');

      // Exactly one attribute, shifted by the marker's length (5 chars:
      // '  1. '), NOT expanded to cover the whole paragraph.
      expect(edit.relativeAttributes, hasLength(1));
      final link = edit.relativeAttributes.first;
      expect(link.type, AttributeType.link);
      expect(link.start, linkStart + 5);
      expect(link.end, linkEnd + 5);
      expect(link.end - link.start, equals(linkEnd - linkStart)); // unchanged length
      expect(link.end - link.start, lessThan(edit.text.length)); // never the whole paragraph

      _apply(engine, edit);
      // After applying, the link must have survived at exactly the
      // shifted position, not spread across the reconstructed text.
      final restored = engine.document.attributeStore.findAt(link.start + 1, type: AttributeType.link);
      expect(restored, isNotEmpty);
      final afterLink = engine.document.attributeStore.findAt(link.end + 1, type: AttributeType.link);
      expect(afterLink, isEmpty); // confirms it did NOT spread past the word
    });
  });

  group('listToggleEdit — numbered renumbering, reproduces the 1,2,1,4,5 bug', () {
    test('toggling item 3 off then back on restores 1,2,3,4,5', () {
      final engine = _engineFor('1. Item one\n2. Item two\n3. Item three\n4. Item four\n5. Item five');
      final item3Start = engine.document.text.indexOf('3. Item three');

      final offEdit = engine.listToggleEdit(EditorSelection.collapsed(item3Start), ParagraphListType.numbered);
      expect(offEdit, isNotNull);
      _apply(engine, offEdit!);

      // Item 3 is now plain; items 4-5 should have renumbered down to 1-2
      // (they're a separate list now, split by the de-listed paragraph).
      expect(engine.document.text, isNot(contains('3. Item three')));
      expect(engine.document.text, contains('1. Item four'));
      expect(engine.document.text, contains('2. Item five'));

      final plainItem3Start = engine.document.text.indexOf('Item three');
      final onEdit = engine.listToggleEdit(EditorSelection.collapsed(plainItem3Start), ParagraphListType.numbered);
      expect(onEdit, isNotNull);
      _apply(engine, onEdit!);

      expect(
        engine.document.text,
        '1. Item one\n2. Item two\n3. Item three\n4. Item four\n5. Item five',
      );
    });

    test('mixed selection (some list, some plain) turns fully on, not decided by the first paragraph', () {
      final engine = _engineFor('1. Already numbered\nPlain paragraph');
      final selection = EditorSelection(baseOffset: 0, extentOffset: engine.document.text.length);
      final edit = engine.listToggleEdit(selection, ParagraphListType.numbered);
      expect(edit, isNotNull);
      expect(edit!.text, contains('1. Already numbered'));
      expect(edit.text, contains('2. Plain paragraph'));
    });
  });

  group('listIndentEdit', () {
    test('indents a single list paragraph by 2 spaces', () {
      final engine = _engineFor('- Item');
      final edit = engine.listIndentEdit(EditorSelection.collapsed(0), outdent: false);
      expect(edit, isNotNull);
      expect(edit!.text, '  - Item');
    });

    test('outdent removes up to 2 spaces, no-ops at top level', () {
      final engine = _engineFor('- Item');
      final edit = engine.listIndentEdit(EditorSelection.collapsed(0), outdent: true);
      expect(edit, isNull);
    });

    test('multi-paragraph indent preserves inline attributes on each paragraph', () {
      const text = '- Item A\n- Bold B';
      final boldStart = text.indexOf('Bold');
      final boldEnd = boldStart + 'Bold'.length;
      final engine = _engineFor(text, [
        TextAttribute(start: boldStart, end: boldEnd, type: AttributeType.bold),
      ]);
      final selection = EditorSelection(baseOffset: 0, extentOffset: text.length);
      final edit = engine.listIndentEdit(selection, outdent: false);
      expect(edit, isNotNull);
      expect(edit!.relativeAttributes.any((a) => a.type == AttributeType.bold), isTrue);
    });

    test('a non-list paragraph in the selection passes through unchanged', () {
      const text = '- Item\nPlain line';
      final engine = _engineFor(text);
      final selection = EditorSelection(baseOffset: 0, extentOffset: text.length);
      final edit = engine.listIndentEdit(selection, outdent: false);
      expect(edit, isNotNull);
      expect(edit!.text, contains('Plain line'));
      expect(edit.text, '  - Item\nPlain line');
    });
  });

  group('deleteBackwardEdit — the exact reported crash scenario', () {
    test('backspacing an empty numbered item mid-list does not throw', () {
      final engine = _engineFor('1. \n2. Something\n3. Something else');
      final markerEnd = '1. '.length;
      expect(
            () => engine.deleteBackwardEdit(EditorSelection.collapsed(markerEnd)),
        returnsNormally,
      );
    });

    test('backspacing an empty numbered item mid-list renumbers correctly', () {
      final engine = _engineFor('1. \n2. Something\n3. Something else');
      final markerEnd = '1. '.length;
      final edit = engine.deleteBackwardEdit(EditorSelection.collapsed(markerEnd));
      expect(edit, isNotNull);
      _applyWithCursor(engine, edit!);
      expect(engine.document.text, '1. Something\n2. Something else');
    });

    test('backspacing an empty item preserves attributes on subsequent items', () {
      const text = '1. \n2. Bold word here';
      final boldStart = text.indexOf('Bold');
      final boldEnd = boldStart + 'Bold'.length;
      final engine = _engineFor(text, [
        TextAttribute(start: boldStart, end: boldEnd, type: AttributeType.bold),
      ]);
      final markerEnd = '1. '.length;
      final edit = engine.deleteBackwardEdit(EditorSelection.collapsed(markerEnd));
      expect(edit, isNotNull);
      expect(edit!.relativeAttributes.any((a) => a.type == AttributeType.bold), isTrue);
      _applyWithCursor(engine, edit);
      expect(engine.document.text, '1. Bold word here');
    });

    test('backspacing a bullet marker with no following list is a plain, non-throwing removal', () {
      final engine = _engineFor('  - Solo item');
      final markerEnd = '  - '.length;
      expect(
            () => engine.deleteBackwardEdit(EditorSelection.collapsed(markerEnd)),
        returnsNormally,
      );
      final edit = engine.deleteBackwardEdit(EditorSelection.collapsed(markerEnd));
      expect(edit!.text, '');
      expect(edit.relativeAttributes, isEmpty);
    });
  });

  group('deleteForwardEdit', () {
    test('deleting right before a marker removes the whole marker in one step', () {
      final engine = _engineFor('  - Item one');
      final edit = engine.deleteForwardEdit(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      expect(edit!.text, '');
      expect(edit.start, 0);
      expect(edit.end, '  - '.length);
    });

    test('deleting elsewhere (not at a marker boundary) is a plain single-character delete', () {
      final engine = _engineFor('Hello');
      final edit = engine.deleteForwardEdit(EditorSelection.collapsed(1));
      expect(edit, isNotNull);
      expect(edit!.start, 1);
      expect(edit.end, 2);
      expect(edit.text, '');
    });

    test('reuses the same renumbering as backspace when deleting a numbered marker mid-list', () {
      final engine = _engineFor('1. First\n2. Second\n3. Third');
      final edit = engine.deleteForwardEdit(EditorSelection.collapsed(0)); // right before "1. "
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, 'First\n1. Second\n2. Third');
    });
  });

  group('enterKeyEditWithRenumber — reproduces the mid-line-split duplicate-number bug', () {
    test('mid-line split renumbers every subsequent item', () {
      final engine = _engineFor('1. First item\n2. Hello World\n3. Third item\n4. Fourth item\n5. Fifth item');
      final splitAt = engine.document.text.indexOf('Hello') + 'Hello'.length; // "Hello| World"

      final edit = engine.enterKeyEditWithRenumber(EditorSelection.collapsed(splitAt), const {});
      _applyWithCursor(engine, edit);

      final finalText = engine.document.text;
      expect(finalText, contains('2. Hello'));
      expect(finalText, contains('3.  World')); // double space is correct: Enter never trims
      expect(finalText, contains('4. Third item'));
      expect(finalText, contains('5. Fourth item'));
      expect(finalText, contains('6. Fifth item'));
    });

    test('end-of-line Enter with nothing to renumber falls back to plain continuation', () {
      final engine = _engineFor('1. Only item');
      final caret = engine.document.text.length;
      final edit = engine.enterKeyEditWithRenumber(EditorSelection.collapsed(caret), const {});
      expect(edit.text, '\n2. ');
    });

    test('sticky attributes apply only to the new marker, never to reconstructed content', () {
      final engine = _engineFor('1. First\n2. Second');
      final caret = engine.document.text.indexOf('First') + 'First'.length;
      final edit = engine.enterKeyEditWithRenumber(
        EditorSelection.collapsed(caret),
        {AttributeType.link: 'https://example.com'},
      );
      for (final attr in edit.relativeAttributes.where((a) => a.type == AttributeType.link)) {
        expect(attr.end, lessThanOrEqualTo(edit.cursorOffsetFromStart));
      }
    });

    test('preserves an existing attribute on reconstructed subsequent content', () {
      const text = '1. First\n2. Bold Second';
      final boldStart = text.indexOf('Bold');
      final boldEnd = boldStart + 'Bold'.length;
      final engine = _engineFor(text, [
        TextAttribute(start: boldStart, end: boldEnd, type: AttributeType.bold),
      ]);
      final caret = engine.document.text.indexOf('First') + 'First'.length;
      final edit = engine.enterKeyEditWithRenumber(EditorSelection.collapsed(caret), const {});
      expect(edit.relativeAttributes.any((a) => a.type == AttributeType.bold), isTrue);
    });
  });

  group('clearFormattingListEdit', () {
    test('returns null when nothing in range has a marker', () {
      final engine = _engineFor('Plain paragraph');
      final selection = EditorSelection(baseOffset: 0, extentOffset: 15);
      expect(engine.clearFormattingListEdit(selection), isNull);
    });

    test('strips markers and preserves inline attributes across a mixed selection', () {
      const text = '  - Bold item\nPlain paragraph';
      final boldStart = text.indexOf('Bold');
      final boldEnd = boldStart + 'Bold'.length;
      final engine = _engineFor(text, [
        TextAttribute(start: boldStart, end: boldEnd, type: AttributeType.bold),
      ]);
      final selection = EditorSelection(baseOffset: 0, extentOffset: text.length);
      final edit = engine.clearFormattingListEdit(selection);
      expect(edit, isNotNull);
      expect(edit!.text, isNot(contains('- ')));
      expect(edit.relativeAttributes.any((a) => a.type == AttributeType.bold), isTrue);
    });

    test('clearFormatting itself strips list markers as one undoable operation', () {
      final engine = _engineFor('  - Item one\n  - Item two');
      final selection = EditorSelection(baseOffset: 0, extentOffset: engine.document.text.length);
      engine.clearFormatting(selection);
      expect(engine.document.text, 'Item one\nItem two');
    });
  });

  group('repairListNumbering', () {
    test('renumbers an out-of-order run to sequential', () {
      final engine = _engineFor('1. A\n5. B\n3. C');
      final edit = engine.repairListNumbering(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, '1. A\n2. B\n3. C');
    });

    test('returns null when the run is already correct — avoids a needless no-op edit', () {
      final engine = _engineFor('1. A\n2. B');
      expect(engine.repairListNumbering(EditorSelection.collapsed(0)), isNull);
    });

    test('falls back to the next paragraph when the cursor lands on non-numbered text', () {
      // Reproduces the "paste orphaned this paragraph's own marker,
      // but a numbered run immediately follows" shape: the cursor's
      // own paragraph isn't numbered, but the very next one is and
      // needs fixing.
      final engine = _engineFor('Plain\n5. B\n6. C');
      final edit = engine.repairListNumbering(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, 'Plain\n1. B\n2. C');
    });

    test('returns null when neither the cursor paragraph nor the next one is numbered', () {
      final engine = _engineFor('Plain one\nPlain two');
      expect(engine.repairListNumbering(EditorSelection.collapsed(0)), isNull);
    });

    test('reproduces the Paste-and-Repair scenario: broken external numbering re-sequences on merge', () {
      // "1. Apple\n1. Banana\n1. Cherry" pasted into the middle of an
      // existing list — simulated here as the post-paste document
      // state directly, since the repair check only needs the merged
      // result, not the paste mechanics themselves.
      final engine = _engineFor('1. First\n1. Apple\n1. Banana\n1. Cherry\n2. Last');
      final edit = engine.repairListNumbering(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, '1. First\n2. Apple\n3. Banana\n4. Cherry\n5. Last');
    });

    test('preserves inline attributes while repairing', () {
      const text = '1. A\n5. Bold B\n3. C';
      final boldStart = text.indexOf('Bold');
      final boldEnd = boldStart + 'Bold'.length;
      final engine = _engineFor(text, [
        TextAttribute(start: boldStart, end: boldEnd, type: AttributeType.bold),
      ]);
      final edit = engine.repairListNumbering(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      expect(edit!.relativeAttributes.any((a) => a.type == AttributeType.bold), isTrue);
    });
  });

  group('surrogate-pair safety — reproduces the emoji-backspace crash risk', () {
    test('backspace right after an astral character deletes the whole surrogate pair, not half', () {
      // U+1F600 (😀) encodes as the UTF-16 surrogate pair \uD83D\uDE00 —
      // 'X😀Y'.length == 4, not 3. Backspacing at position 3 (right
      // after the emoji) with the old code-unit-naive fallback would
      // delete only the low surrogate (position 2), leaving an
      // orphaned, invalid high surrogate behind.
      final engine = _engineFor('X😀Y');
      expect(engine.document.text.length, 4);
      final edit = engine.deleteBackwardEdit(EditorSelection.collapsed(3));
      expect(edit, isNotNull);
      expect(edit!.start, 1);
      expect(edit.end, 3);
      _applyWithCursor(engine, edit);
      expect(engine.document.text, 'XY');
    });

    test('forward-delete right before an astral character deletes the whole surrogate pair', () {
      final engine = _engineFor('X😀Y');
      final edit = engine.deleteForwardEdit(EditorSelection.collapsed(1));
      expect(edit, isNotNull);
      expect(edit!.start, 1);
      expect(edit.end, 3);
      _apply(engine, edit);
      expect(engine.document.text, 'XY');
    });

    test('backspace on an ordinary (non-surrogate) character is unaffected', () {
      final engine = _engineFor('Hello');
      final edit = engine.deleteBackwardEdit(EditorSelection.collapsed(5));
      expect(edit, isNotNull);
      expect(edit!.start, 4);
      expect(edit.end, 5);
    });
  });

  group('toggleCheckedEdit', () {
    test('promotes a plain paragraph to a fresh unchecked task item', () {
      final engine = _engineFor('Buy milk');
      final edit = engine.toggleCheckedEdit(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, '  - [ ] Buy milk');
    });

    test('adds an unchecked checkbox to a plain bullet', () {
      final engine = _engineFor('- Buy milk');
      final edit = engine.toggleCheckedEdit(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, '- [ ] Buy milk');
    });

    test('flips an unchecked item to checked', () {
      final engine = _engineFor('- [ ] Buy milk');
      final edit = engine.toggleCheckedEdit(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, '- [x] Buy milk');
    });

    test('flips a checked item back to unchecked', () {
      final engine = _engineFor('- [x] Buy milk');
      final edit = engine.toggleCheckedEdit(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, '- [ ] Buy milk');
    });

    test('is a no-op on a numbered item — numbered lists are not task-list-compatible', () {
      final engine = _engineFor('1. Buy milk');
      final edit = engine.toggleCheckedEdit(EditorSelection.collapsed(0));
      expect(edit, isNull);
    });

    test('preserves an inline attribute, shifted to match the new marker length', () {
      const text = 'Buy Bold milk';
      final boldStart = text.indexOf('Bold');
      final boldEnd = boldStart + 'Bold'.length;
      final engine = _engineFor(text, [
        TextAttribute(start: boldStart, end: boldEnd, type: AttributeType.bold),
      ]);
      final edit = engine.toggleCheckedEdit(EditorSelection.collapsed(0));
      expect(edit, isNotNull);
      _apply(engine, edit!);
      final markerLen = '  - [ ] '.length;
      final restored = engine.document.attributeStore.findAt(markerLen + boldStart + 1, type: AttributeType.bold);
      expect(restored, isNotEmpty);
    });

    test('a mixed multi-paragraph selection toggles each paragraph independently', () {
      final engine = _engineFor('- [ ] One\n- [x] Two\nThree');
      final selection = EditorSelection(baseOffset: 0, extentOffset: engine.document.text.length);
      final edit = engine.toggleCheckedEdit(selection);
      expect(edit, isNotNull);
      _apply(engine, edit!);
      expect(engine.document.text, '- [x] One\n- [ ] Two\n  - [ ] Three');
    });
  });

  group('setAlignment', () {
    test('sets alignment on the paragraph containing a collapsed caret', () {
      final engine = _engineFor('line one\nline two');
      engine.setAlignment(EditorSelection.collapsed(11), ParagraphAlignment.center);
      final lineTwoStart = 'line one\n'.length;
      expect(engine.document.paragraphs.paragraphAt(lineTwoStart)!.alignment, ParagraphAlignment.center);
      expect(engine.document.paragraphs.paragraphAt(3)!.alignment, isNull); // "line one" untouched
    });

    test('null clears alignment', () {
      final engine = _engineFor('Some text');
      engine.setAlignment(EditorSelection.collapsed(0), ParagraphAlignment.right);
      engine.setAlignment(EditorSelection.collapsed(0), null);
      expect(engine.document.paragraphs.paragraphAt(0)!.alignment, isNull);
    });

    test('does not change text length or content', () {
      final engine = _engineFor('Some text');
      engine.setAlignment(EditorSelection.collapsed(0), ParagraphAlignment.center);
      expect(engine.document.text, 'Some text');
    });
  });

  group('setTextDirection', () {
    test('sets textDirection on the paragraph containing a collapsed caret', () {
      final engine = _engineFor('line one\nline two');
      engine.setTextDirection(EditorSelection.collapsed(11), ParagraphTextDirection.rtl);
      final lineTwoStart = 'line one\n'.length;
      expect(engine.document.paragraphs.paragraphAt(lineTwoStart)!.textDirection, ParagraphTextDirection.rtl);
      expect(engine.document.paragraphs.paragraphAt(3)!.textDirection, isNull); // "line one" untouched
    });

    test('null clears textDirection', () {
      final engine = _engineFor('Some text');
      engine.setTextDirection(EditorSelection.collapsed(0), ParagraphTextDirection.rtl);
      engine.setTextDirection(EditorSelection.collapsed(0), null);
      expect(engine.document.paragraphs.paragraphAt(0)!.textDirection, isNull);
    });

    test('does not change text length or content', () {
      final engine = _engineFor('Some text');
      engine.setTextDirection(EditorSelection.collapsed(0), ParagraphTextDirection.rtl);
      expect(engine.document.text, 'Some text');
    });
  });

  group('autoFormatHeaderLevel', () {
    test('a single # at paragraph start is h1', () {
      final engine = _engineFor('#');
      expect(engine.autoFormatHeaderLevel(1), 'h1');
    });

    test('two through six #s collapse to h2, matching MarkdownImporter', () {
      for (final hashes in ['##', '###', '####', '#####', '######']) {
        final engine = _engineFor(hashes);
        expect(engine.autoFormatHeaderLevel(hashes.length), 'h2', reason: hashes);
      }
    });

    test('seven #s is not a header shortcut', () {
      final engine = _engineFor('#######');
      expect(engine.autoFormatHeaderLevel(7), isNull);
    });

    test('anything other than bare hashes before the caret does not trigger', () {
      final engine = _engineFor('not a #heading');
      expect(engine.autoFormatHeaderLevel(14), isNull);
    });

    test('a # that is not at the very start of the paragraph does not trigger', () {
      final engine = _engineFor('line one\n line two #');
      final caret = 'line one\n line two #'.length;
      expect(engine.autoFormatHeaderLevel(caret), isNull);
    });

    test('only checks the paragraph containing spaceInsertPos, not the whole document', () {
      final engine = _engineFor('# Already a heading\n#');
      final secondParagraphCaret = engine.document.text.length;
      expect(engine.autoFormatHeaderLevel(secondParagraphCaret), 'h1');
    });
  });
}