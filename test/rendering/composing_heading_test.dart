// A heading must look like a heading while the keyboard is still composing the word.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);

  const roboto = TextStyle(fontFamily: 'Roboto');

  double sizeAt(RichEditorController c, int offset, {TextRange? composing}) {
    c.renderer.activeRowMetrics = c.renderer.rowMetrics(textScaler: TextScaler.noScaling, style: roboto);
    final span = c.renderer.renderSpan(c.document, style: roboto, composingRange: composing, textScaler: TextScaler.noScaling);
    var pos = 0;
    for (final child in (span.children ?? const <InlineSpan>[]).cast<TextSpan>()) {
      final len = child.text!.length;
      if (offset < pos + len) return child.style!.fontSize ?? notebookTheme.baseFontSize;
      pos += len;
    }
    return span.style?.fontSize ?? notebookTheme.baseFontSize;
  }

  test('the composing word of a heading is drawn at the heading size', () {
    final c = RichEditorController(text: 'Shopping', theme: notebookTheme);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 8);
    final plain = sizeAt(c, 2);
    c.setHeader('h1');
    final composing = const TextRange(start: 0, end: 8);
    expect(sizeAt(c, 2, composing: composing), greaterThan(plain), reason: 'composing: heading size');
    expect(sizeAt(c, 2), greaterThan(plain), reason: 'not composing: heading size');
    expect(sizeAt(c, 2, composing: composing), sizeAt(c, 2));
  });

  test('applying a heading changes what is drawn straight away, without another keystroke', () {
    final c = RichEditorController(text: 'Shopping', theme: notebookTheme);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 8);
    var notified = 0;
    c.addListener(() => notified++);
    final before = sizeAt(c, 2, composing: const TextRange(start: 0, end: 8));
    c.setHeader('h1');
    expect(notified, greaterThan(0));
    expect(sizeAt(c, 2, composing: const TextRange(start: 0, end: 8)), isNot(before));
  });
  test('a note that is only heading lines is drawn as headings: one line, or several of the same level', () {
    final one = RichEditorController(text: 'Shopping', theme: notebookTheme);
    addTearDown(one.dispose);
    final plain = sizeAt(one, 2);
    final sizes = <String, double>{};
    for (final level in ['h1', 'h2', 'h3']) {
      one.selection = const TextSelection.collapsed(offset: 3);
      one.setHeader(level);
      sizes[level] = sizeAt(one, 2);
      expect(sizes[level], greaterThan(plain), reason: '$level on its own');
    }
    expect(sizes['h1'], greaterThan(sizes['h2']!));
    expect(sizes['h2'], greaterThan(sizes['h3']!));

    one.setHeader(null);
    expect(sizeAt(one, 2), plain, reason: 'taking the heading off puts the plain look back');

    final two = RichEditorController(text: 'One\nTwo', theme: notebookTheme);
    addTearDown(two.dispose);
    for (final at in [0, 4]) {
      two.selection = TextSelection.collapsed(offset: at);
      two.setHeader('h1');
    }
    expect(sizeAt(two, 1), greaterThan(plain), reason: 'first of two headings');
    expect(sizeAt(two, 5), greaterThan(plain), reason: 'second of two headings');
  });
}
