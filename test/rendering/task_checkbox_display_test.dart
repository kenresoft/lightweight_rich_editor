// A task item ('- [ ] ' / '- [x] ') is drawn as a checkbox glyph, but stays exactly
// as many characters as the stored marker, so every offset still lines up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

String _shown(RichEditorController c) {
  final span = c.renderer.renderSpan(c.document, style: const TextStyle(fontSize: 16));
  final buffer = StringBuffer();
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) buffer.write(s.text);
    return true;
  });
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unchecked and checked items show a box and a tick, same length as the marker', () {
    final c = RichEditorController(text: '- [ ] open\n- [x] done\n  - [ ] nested', theme: notebookTheme);
    addTearDown(c.dispose);
    final shown = _shown(c);

    expect(shown.length, c.document.text.length, reason: 'every offset must still line up');
    expect(shown, contains('☐'));
    expect(shown, contains('☒'));
    expect(shown, isNot(contains('[ ]')));
    expect(shown, isNot(contains('[x]')));
    expect(shown.split('\n').first.endsWith('open'), isTrue);
    expect(shown.split('\n').last.startsWith('  ☐'), isTrue, reason: 'indent is kept');
  });

  test('plain bullets still draw a dot and numbers are untouched', () {
    final c = RichEditorController(text: '- one\n1. two', theme: notebookTheme);
    addTearDown(c.dispose);
    final shown = _shown(c);
    expect(shown.length, c.document.text.length);
    expect(shown, startsWith('• one'));
    expect(shown, contains('1. two'));
  });
}
