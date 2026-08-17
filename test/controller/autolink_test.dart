import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  group('RichEditorController autolink', () {
    test('updates existing link target when text is edited', () {
      final controller = RichEditorController();
      
      // Type google.com 
      controller.value = const TextEditingValue(
        text: 'Visit google.com ',
        selection: TextSelection.collapsed(offset: 17),
      );
      
      expect(controller.document.attributes.any((a) => a.type == AttributeType.link), isTrue);
      final initialLink = controller.document.attributes.firstWhere((a) => a.type == AttributeType.link);
      expect(initialLink.value, 'https://google.com');

      // Edit Visit google.com | to Visit google.org|
      controller.value = const TextEditingValue(
        text: 'Visit google.org',
        selection: TextSelection.collapsed(offset: 16),
      );
      
      // Type a space to trigger autolink update
      controller.value = const TextEditingValue(
        text: 'Visit google.org ',
        selection: TextSelection.collapsed(offset: 17),
      );

      final updatedLink = controller.document.attributes.firstWhere((a) => a.type == AttributeType.link);
      expect(updatedLink.value, 'https://google.org');
    });

    test('a trailing comma right before the boundary is excluded from the link', () {
      // Regression test: "https://example.com," typed then a boundary
      // char (space/newline/tab) used to linkify the comma along with
      // the URL, since detectUrlBeforeBoundary never trimmed trailing
      // punctuation the way the paste-path detectAllUrls already did.
      final controller = RichEditorController();

      // One `value =` assignment per character -- genuine live typing,
      // exactly how a real `TextField` reports each keystroke as its
      // own diff (never a bulk multi-character jump; see
      // `_maybeAutolink`'s doc comment on why that distinction matters
      // now that a bulk diff is deliberately treated as an
      // already-finished chunk, not "still being typed").
      const typed = 'Visit https://example.com,';
      for (var i = 0; i < typed.length; i++) {
        final newText = controller.document.text + typed[i];
        controller.value = controller.value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
      // The comma isn't itself a boundary char -- nothing should have
      // linkified yet, matching the existing "don't linkify while still
      // typing" contract.
      expect(controller.document.attributes.any((a) => a.type == AttributeType.link), isFalse);

      controller.value = const TextEditingValue(
        text: 'Visit https://example.com, ',
        selection: TextSelection.collapsed(offset: 28),
      );

      final link = controller.document.attributes.firstWhere((a) => a.type == AttributeType.link);
      expect(controller.document.text.substring(link.start, link.end), 'https://example.com');
      expect(link.value, 'https://example.com');
    });

    // Regression test for a real, reported bug found via live testing on
    // a real Android device: a native on-screen keyboard's own clipboard
    // paste (e.g. Gboard's clipboard suggestion strip) commits the
    // pasted text directly through `TextInputClient.updateEditingValue`
    // -- i.e. through this exact `controller.value = ...` path, handled
    // identically to a live keystroke -- rather than through
    // `ClipboardManager.paste()`/the Paste toolbar button. Before this
    // fix, `_maybeAutolink` only ever inspected the single token right
    // before the *last* character of a multi-character diff, so a
    // multi-line bulk paste containing several URLs, none of them
    // followed by a boundary character at the very end of the whole
    // pasted block (the common case: pasted text rarely ends with a
    // trailing space), linked *none* of them at all.
    test('a bulk multi-URL insert (simulating a real device\'s IME-driven paste) links every URL, even with no trailing boundary character', () {
      final controller = RichEditorController();

      // A single `value =` assignment carrying the *entire* multi-line
      // block in one shot -- exactly how a keyboard's own paste commits
      // it, and distinct from typing it character-by-character.
      const pasted =
          'Production Apps:\n'
          'https://play.google.com/store/apps/details?id=com.phunplan.phunplan, \n'
          'https://apps.apple.com/app/6763565579,\n'
          'https://play.google.com/store/apps/details?id=com.telomii.telomii,\n'
          'https://play.google.com/store/apps/details?id=com.lfb.desktopbrowser';
      controller.value = TextEditingValue(
        text: pasted,
        selection: TextSelection.collapsed(offset: pasted.length),
      );

      final links = controller.document.attributes.where((a) => a.type == AttributeType.link).toList();
      expect(links, hasLength(4));
      expect(links[0].value, 'https://play.google.com/store/apps/details?id=com.phunplan.phunplan');
      expect(links[1].value, 'https://apps.apple.com/app/6763565579');
      expect(links[2].value, 'https://play.google.com/store/apps/details?id=com.telomii.telomii');
      expect(links[3].value, 'https://play.google.com/store/apps/details?id=com.lfb.desktopbrowser');
    });

    // Regression test for a second, follow-on bug reported after the one
    // above was fixed: autolinking each URL via its own separate
    // `commands.setLink` call after the text was already inserted put
    // every one of them on the undo stack as its own step. A single
    // bulk paste with 4 URLs took 5 presses of undo to fully revert --
    // 4 "peeling back one link at a time", then a 5th for the text
    // itself -- instead of the text and all its autolinks vanishing
    // together on the very first undo, the way every other editor
    // treats "undo the paste".
    test('undoing a bulk multi-URL paste removes the text and all its autolinks in a single step', () {
      final controller = RichEditorController(text: 'before ');
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 'before '.length),
      );

      const pasted = 'https://a.example.com, https://b.example.com, https://c.example.com';
      final newText = controller.document.text + pasted;
      controller.value = controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );

      expect(
        controller.document.attributes.where((a) => a.type == AttributeType.link),
        hasLength(3),
      );
      expect(controller.canUndo, isTrue);

      controller.undo();

      expect(controller.document.text, 'before ');
      expect(controller.document.attributes.where((a) => a.type == AttributeType.link), isEmpty);
      // Confirms the paste really was a single undo-stack entry, not
      // several -- there's nothing left to undo back to an intermediate,
      // partially-unlinked state.
      expect(controller.canUndo, isFalse);
    });

    test('a bulk two-character insert still does not autolink an incomplete-looking token', () {
      // A bulk (non-single-character) diff whose content just isn't
      // URL-shaped at all -- confirms the new multi-character branch
      // doesn't spuriously link ordinary short bulk replacements (e.g.
      // an autocorrect word swap).
      final controller = RichEditorController(text: 'hi');
      controller.value = controller.value.copyWith(text: 'ok', selection: const TextSelection.collapsed(offset: 2));

      expect(controller.document.attributes.any((a) => a.type == AttributeType.link), isFalse);
    });

    test('live single-character typing still does not autolink mid-URL (unchanged behavior)', () {
      final controller = RichEditorController();
      const url = 'https://example.com';
      for (var i = 0; i < url.length; i++) {
        final newText = controller.document.text + url[i];
        controller.value = controller.value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }

      expect(controller.document.attributes.any((a) => a.type == AttributeType.link), isFalse);
    });
  });
}
