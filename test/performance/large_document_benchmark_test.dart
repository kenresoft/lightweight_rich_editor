// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

/// Not a correctness test -- prints real wall-clock timings for editing
/// operations on a large, heavily-formatted document, so "is this editor
/// performant for large notes" has actual numbers behind it instead of
/// a guess. Run with `flutter test test/performance -r expanded` to see
/// the printed timings; the `expect` calls are loose upper bounds meant
/// to catch a genuine regression (an accidental O(n^2) reintroduced
/// somewhere), not to assert a specific target.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ~3,000 paragraphs, ~230KB of text, ~450 formatting spans scattered
  // throughout (bold/italic/link on roughly every 5th-10th paragraph) --
  // representative of a genuinely large, heavily-formatted note, well
  // beyond what a normal note-taking session produces.
  const paragraphCount = 3000;
  final buffer = StringBuffer();
  final attributes = <TextAttribute>[];
  for (var p = 0; p < paragraphCount; p++) {
    if (p > 0) buffer.write('\n');
    final start = buffer.length;
    final line =
        'Paragraph $p: the quick brown fox jumps over the lazy dog near the riverbank while the sun sets slowly.';
    buffer.write(line);
    if (p % 7 == 0) {
      attributes.add(TextAttribute(start: start + 12, end: start + 30, type: AttributeType.bold));
    }
    if (p % 11 == 0) {
      attributes.add(TextAttribute(start: start + 31, end: start + 50, type: AttributeType.italic));
    }
    if (p % 23 == 0) {
      attributes.add(TextAttribute(
        start: start,
        end: start + 11,
        type: AttributeType.link,
        value: 'https://example.com/p$p',
      ));
    }
  }
  final text = buffer.toString();

  print('--- Large-document benchmark: ${text.length} chars, $paragraphCount paragraphs, ${attributes.length} spans ---');

  test('constructing the controller for a large document', () {
    final sw = Stopwatch()..start();
    final controller = RichEditorController(text: text, initialAttributes: attributes);
    sw.stop();
    print('Controller construction: ${sw.elapsedMilliseconds}ms');
    addTearDown(controller.dispose);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test('cold buildTextSpan over the whole document', () {
    final controller = RichEditorController(text: text, initialAttributes: attributes);
    addTearDown(controller.dispose);
    const style = TextStyle(fontSize: 16);

    final sw = Stopwatch()..start();
    controller.renderer.renderSpan(controller.document, style: style);
    sw.stop();
    print('Cold buildTextSpan (full document): ${sw.elapsedMilliseconds}ms');
    // Measured ~43ms after the paragraph-boundary-event optimization
    // (down from ~143ms before it) -- 500ms leaves generous headroom
    // for a slower CI host while still catching a real regression back
    // toward the old order of magnitude.
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('warm (cached) buildTextSpan re-render is effectively free', () {
    final controller = RichEditorController(text: text, initialAttributes: attributes);
    addTearDown(controller.dispose);
    const style = TextStyle(fontSize: 16);
    controller.renderer.renderSpan(controller.document, style: style); // warm the cache

    final sw = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      controller.renderer.renderSpan(controller.document, style: style);
    }
    sw.stop();
    print('100 cache-hit buildTextSpan calls: ${sw.elapsedMilliseconds}ms (${sw.elapsedMicroseconds / 100}µs each)');
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  test('typing 50 sequential characters near the end of the document (best case)', () {
    final controller = RichEditorController(text: text, initialAttributes: attributes);
    addTearDown(controller.dispose);
    const style = TextStyle(fontSize: 16);
    controller.renderer.renderSpan(controller.document, style: style); // warm

    var current = controller.value;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      final newText = '${current.text}x';
      current = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length));
      controller.value = current;
      // Mirrors what the real TextField does every frame after a value change.
      controller.renderer.renderSpan(controller.document, style: style);
    }
    sw.stop();
    print('50 keystrokes at document end (edit + rebuild each): ${sw.elapsedMilliseconds}ms '
        '(${sw.elapsedMilliseconds / 50}ms/keystroke)');
    // Measured ~7.5-8.7ms/keystroke after the paragraph-boundary-event
    // optimization (down from ~33-36ms/keystroke before it — well over
    // a 60fps frame budget). 20ms leaves headroom for a slower CI host
    // while still catching a real regression back toward the old
    // order of magnitude, which this exact benchmark caught live.
    expect(sw.elapsedMilliseconds / 50, lessThan(20));
  });

  test('typing 50 sequential characters in the middle of the document (worst case for shifting)', () {
    final controller = RichEditorController(text: text, initialAttributes: attributes);
    addTearDown(controller.dispose);
    const style = TextStyle(fontSize: 16);
    controller.renderer.renderSpan(controller.document, style: style); // warm

    final midpoint = text.length ~/ 2;
    var currentText = text;
    var offset = midpoint;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      currentText = '${currentText.substring(0, offset)}x${currentText.substring(offset)}';
      offset += 1;
      controller.value = TextEditingValue(text: currentText, selection: TextSelection.collapsed(offset: offset));
      controller.renderer.renderSpan(controller.document, style: style);
    }
    sw.stop();
    print('50 keystrokes mid-document (edit + rebuild each): ${sw.elapsedMilliseconds}ms '
        '(${sw.elapsedMilliseconds / 50}ms/keystroke)');
    // Measured ~7.5-8.7ms/keystroke after the paragraph-boundary-event
    // optimization (down from ~33-36ms/keystroke before it — well over
    // a 60fps frame budget). 20ms leaves headroom for a slower CI host
    // while still catching a real regression back toward the old
    // order of magnitude, which this exact benchmark caught live.
    expect(sw.elapsedMilliseconds / 50, lessThan(20));
  });

  test('applying bold to a selection and undoing it', () {
    final controller = RichEditorController(text: text, initialAttributes: attributes);
    addTearDown(controller.dispose);
    controller.value = controller.value.copyWith(
      selection: TextSelection(baseOffset: text.length ~/ 2, extentOffset: text.length ~/ 2 + 5000),
    );

    final sw = Stopwatch()..start();
    controller.toggleBold();
    sw.stop();
    print('toggleBold over a 5,000-char selection: ${sw.elapsedMilliseconds}ms');

    final sw2 = Stopwatch()..start();
    controller.undo();
    sw2.stop();
    print('undo of that toggleBold: ${sw2.elapsedMilliseconds}ms');

    expect(sw.elapsedMilliseconds, lessThan(500));
    expect(sw2.elapsedMilliseconds, lessThan(500));
  });

  test('pasting a large multi-paragraph block with several URLs', () {
    final controller = RichEditorController();
    addTearDown(controller.dispose);
    final pasteText = List.generate(
      500,
      (i) => i % 20 == 0 ? 'https://example.com/item/$i' : 'Line $i of pasted content here.',
    ).join('\n');

    final sw = Stopwatch()..start();
    controller.value = TextEditingValue(
      text: pasteText,
      selection: TextSelection.collapsed(offset: pasteText.length),
    );
    sw.stop();
    print('Bulk IME-style paste of ${pasteText.length} chars / 25 URLs: ${sw.elapsedMilliseconds}ms');

    expect(controller.document.attributes.where((a) => a.type == AttributeType.link).length, 25);
    expect(sw.elapsedMilliseconds, lessThan(500));
  });
}
