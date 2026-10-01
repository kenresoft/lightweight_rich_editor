// ignore_for_file: avoid_print
//
// The font-size toolbar must report the size that is actually RENDERED and
// must never offer a size that silently renders smaller — with selections,
// collapsed cursors, repeated presses, undo/redo, and oversized imported sizes.
//
// "Rendered" is read from the span the renderer really produces (with real
// Roboto faces), not from the stored attributes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../rendering/notebook_policy_test.dart' show lay, size, header;
import '../support/notebook_test_support.dart';

const _roboto = TextStyle(fontFamily: 'Roboto');

class _Rig {
  _Rig(String text, {List<TextAttribute> attrs = const [], this.scale = 1.0}) {
    c = RichEditorController(text: text, theme: notebookTheme, initialAttributes: attrs);
    _bind();
  }

  late final RichEditorController c;
  final double scale;

  TextScaler get scaler => TextScaler.linear(scale);

  /// What the real `buildTextSpan` records for the toolbar.
  void _bind() => c.renderer.activeRowMetrics = c.renderer.rowMetrics(textScaler: scaler, style: _roboto);

  /// Font size of the run that covers [offset] in the real rendered span.
  double renderedSizeAt(int offset) {
    final span = c.renderer.renderSpan(c.document, style: _roboto, textScaler: scaler);
    var pos = 0;
    for (final child in (span.children ?? const <InlineSpan>[]).cast<TextSpan>()) {
      final len = child.text!.length;
      if (offset < pos + len) return child.style!.fontSize!;
      pos += len;
    }
    return span.style?.fontSize ?? notebookTheme.baseFontSize;
  }

  double get pitch => c.renderer.activeRowMetrics!.pitch;

  /// The toolbar's number must equal the rendered size at the selection.
  void expectToolbarMatchesRender(int offset, [String? why]) {
    expect(c.effectiveFontSize, renderedSizeAt(offset), reason: 'toolbar vs rendered at $offset ${why ?? ''}');
    expect(c.effectiveFontSize, lessThanOrEqualTo(c.maxInlineFontSize));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);

  const word = TextSelection(baseOffset: 0, extentOffset: 5);

  group('the toolbar reports the rendered size and stops at the largest that fits', () {
    final faces = <String, List<void Function(RichEditorController)>>{
      'plain': [],
      'bold': [(c) => c.toggleBold()],
      'italic': [(c) => c.toggleItalic()],
      'bold+italic': [(c) => c.toggleBold(), (c) => c.toggleItalic()],
    };

    for (final scale in [0.85, 1.0, 1.4, 2.0, 3.0]) {
      for (final face in faces.entries) {
        test('${face.key} selection, repeated increase then decrease @scale $scale', () {
          final r = _Rig('hello world', scale: scale);
          addTearDown(r.c.dispose);
          r.c.selection = word;
          for (final f in face.value) {
            f(r.c);
          }
          r.c.selection = word;
          final max = r.c.maxInlineFontSize;

          final seen = <double>[];
          for (var i = 0; i < 60; i++) {
            r.c.increaseFontSize();
            r.c.selection = word;
            r.expectToolbarMatchesRender(2, 'after increase $i');
            seen.add(r.c.effectiveFontSize);
          }
          expect(r.c.effectiveFontSize, max, reason: 'must reach, and stop at, the ceiling');
          expect(r.c.canIncreaseFontSize, isFalse);
          // No size the toolbar ever showed was larger than what renders.
          expect(seen.every((s) => s <= max), isTrue);
          // One more press is a no-op: nothing is stored beyond the ceiling.
          final before = r.c.document.attributes.length;
          r.c.increaseFontSize();
          expect(r.c.document.attributes.length, before);
          final stored = r.c.document.attributes.where((a) => a.type == AttributeType.size).map((a) => (a.value as num).toDouble());
          expect(stored, everyElement(lessThanOrEqualTo(max)));

          for (var i = 0; i < 60; i++) {
            r.c.decreaseFontSize();
            r.c.selection = word;
            r.expectToolbarMatchesRender(2, 'after decrease $i');
          }
          expect(r.c.effectiveFontSize, RichEditorController.minInlineFontSize);
          expect(r.c.canDecreaseFontSize, isFalse);
        });
      }
    }

    test('toggling bold/italic after sizing never leaves the toolbar ahead of the render', () {
      final r = _Rig('hello world');
      addTearDown(r.c.dispose);
      r.c.selection = word;
      for (var i = 0; i < 20; i++) {
        r.c.increaseFontSize();
        r.c.selection = word;
      }
      for (final toggle in [r.c.toggleBold, r.c.toggleItalic, r.c.toggleBold, r.c.toggleItalic]) {
        toggle();
        r.c.selection = word;
        r.expectToolbarMatchesRender(2);
      }
    });
  });

  group('collapsed cursor', () {
    test('size presses at a collapsed cursor apply to what is typed next, bounded by the ceiling', () {
      final r = _Rig('hello');
      addTearDown(r.c.dispose);
      r.c.selection = const TextSelection.collapsed(offset: 5);
      final max = r.c.maxInlineFontSize;
      for (var i = 0; i < 30; i++) {
        r.c.increaseFontSize();
      }
      expect(r.c.effectiveFontSize, max);
      r.c.value = const TextEditingValue(text: 'helloXY', selection: TextSelection.collapsed(offset: 7));
      r.c.selection = const TextSelection.collapsed(offset: 7);
      expect(r.renderedSizeAt(5), max);
      expect(r.renderedSizeAt(6), max);
      expect(r.renderedSizeAt(0), 16.0, reason: 'text before the cursor must not change');
      r.expectToolbarMatchesRender(6);
    });

    test('decrease at a collapsed cursor respects the floor', () {
      final r = _Rig('hello');
      addTearDown(r.c.dispose);
      r.c.selection = const TextSelection.collapsed(offset: 5);
      for (var i = 0; i < 30; i++) {
        r.c.decreaseFontSize();
      }
      expect(r.c.effectiveFontSize, RichEditorController.minInlineFontSize);
      expect(r.c.canDecreaseFontSize, isFalse);
    });
  });

  group('selections spanning different sizes', () {
    test('a mixed selection reports a value the render can honour, and one press unifies it within the ceiling', () {
      final r = _Rig('aaaa bbbb cccc', attrs: [size(5, 9, 22), size(10, 14, 24)]);
      addTearDown(r.c.dispose);
      r.c.selection = const TextSelection(baseOffset: 0, extentOffset: 14);
      // No single size exists; the toolbar must still never exceed the ceiling.
      expect(r.c.effectiveFontSize, lessThanOrEqualTo(r.c.maxInlineFontSize));
      r.c.increaseFontSize();
      r.c.selection = const TextSelection(baseOffset: 0, extentOffset: 14);
      for (final o in [0, 6, 11]) {
        expect(r.renderedSizeAt(o), r.c.effectiveFontSize);
      }
    });

    test('the row stays exactly one pitch through a long mixed-size formatting session', () {
      final r = _Rig('aaaa bbbb cccc dddd');
      addTearDown(r.c.dispose);
      final ranges = [const TextSelection(baseOffset: 0, extentOffset: 4), const TextSelection(baseOffset: 5, extentOffset: 9), const TextSelection(baseOffset: 10, extentOffset: 14)];
      for (var i = 0; i < 40; i++) {
        final sel = ranges[i % 3];
        r.c.selection = sel;
        if (i % 4 == 0) {
          r.c.toggleBold();
          r.c.selection = sel;
        }
        (i % 5 < 3 ? r.c.increaseFontSize : r.c.decreaseFontSize)();
        r.c.selection = sel;
        final laid = lay(r.c.document.text, attrs: List.of(r.c.document.attributes));
        expect(laid.bottoms.length, 1);
        laid.expectEveryLineOneRow();
        r.expectToolbarMatchesRender(sel.start + 1, 'step $i');
      }
    });
  });

  group('undo / redo', () {
    test('every step back and forth reports the rendered size, including at the ceiling', () {
      final r = _Rig('hello world');
      addTearDown(r.c.dispose);
      r.c.selection = word;
      final sizes = <double>[r.c.effectiveFontSize];
      for (var i = 0; i < 12; i++) {
        final before = r.c.effectiveFontSize;
        r.c.increaseFontSize();
        r.c.selection = word;
        if (r.c.effectiveFontSize != before) sizes.add(r.c.effectiveFontSize);
      }
      expect(sizes.last, r.c.maxInlineFontSize);
      for (var i = sizes.length - 2; i >= 0; i--) {
        r.c.undo();
        r.c.selection = word;
        expect(r.c.effectiveFontSize, sizes[i], reason: 'undo to step $i');
        r.expectToolbarMatchesRender(2);
      }
      for (var i = 1; i < sizes.length; i++) {
        r.c.redo();
        r.c.selection = word;
        expect(r.c.effectiveFontSize, sizes[i], reason: 'redo to step $i');
        r.expectToolbarMatchesRender(2);
      }
    });
  });

  group('5. oversized imported inline sizes', () {
    for (final big in [60, 200, 1000]) {
      test('stored $big: preserved, rendered at the ceiling, toolbar agrees, editing does not jump', () {
        final r = _Rig('hello world', attrs: [size(0, 5, big)]);
        addTearDown(r.c.dispose);
        r.c.selection = word;
        final max = r.c.maxInlineFontSize;

        // Stored fidelity is untouched by rendering / selecting / reading.
        expect(r.c.document.attributes.single.value, big);
        expect(r.renderedSizeAt(2), max);
        expect(r.c.effectiveFontSize, max);
        expect(r.c.canIncreaseFontSize, isFalse);
        expect(r.c.document.attributes.single.value, big);

        // Round trip through JSON (save / reopen) keeps the stored value.
        final reopened = EditorDocument.fromJson(r.c.toJson());
        expect(reopened.attributes.single.value, big);

        // Typing inside and at the end of the imported run: no jump.
        r.c.value = const TextEditingValue(text: 'helXlo world', selection: TextSelection.collapsed(offset: 4));
        r.c.value = const TextEditingValue(text: 'helXlo world!', selection: TextSelection.collapsed(offset: 13));
        expect(r.renderedSizeAt(3), max, reason: 'typed inside the oversized run');
        expect(r.renderedSizeAt(8), 16.0, reason: 'text after the run is untouched');
        r.c.selection = const TextSelection.collapsed(offset: 3);
        expect(r.c.effectiveFontSize, max);

        // Stepping down from an oversized run starts from what is SHOWN: one
        // step below the ceiling — never a jump to the stored size or to base.
        r.c.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
        r.c.decreaseFontSize();
        r.c.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
        expect(r.c.effectiveFontSize, max - 2);
        r.expectToolbarMatchesRender(2);
        // And undo brings the imported formatting back exactly.
        r.c.undo();
        expect(r.c.document.attributes.where((a) => a.type == AttributeType.size).map((a) => a.value), contains(big));
        r.c.selection = word;
        expect(r.c.effectiveFontSize, max);
      });
    }

    test('an oversized size combined with bold and italic is bounded by that face\'s own ceiling', () {
      final r = _Rig('hello world', attrs: [
        size(0, 5, 500),
        const TextAttribute(start: 0, end: 5, type: AttributeType.bold),
        const TextAttribute(start: 0, end: 5, type: AttributeType.italic),
      ]);
      addTearDown(r.c.dispose);
      r.c.selection = word;
      r.expectToolbarMatchesRender(2);
      expect(r.c.effectiveFontSize, r.c.maxInlineFontSize);
    });
  });

  group('headings in the toolbar', () {
    for (final level in ['h1', 'h2', 'h3']) {
      test('$level: size controls are disabled and the reported size is the configured Notebook size', () {
        final r = _Rig('Title\nbody');
        addTearDown(r.c.dispose);
        r.c.selection = const TextSelection.collapsed(offset: 2);
        r.c.setHeader(level);
        final expected = {'h1': 24.0, 'h2': 21.0, 'h3': 18.0}[level]!;
        expect(r.c.effectiveFontSize, expected);
        expect(r.renderedSizeAt(2), expected);
        expect(r.c.canIncreaseFontSize, isFalse);
        expect(r.c.canDecreaseFontSize, isFalse);
        final laid = lay('Title\nbody', attrs: [header(0, 5, level)]);
        laid.expectEveryLineOneRow();
      });
    }
  });
}
