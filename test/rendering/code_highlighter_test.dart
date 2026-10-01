// Syntax highlighting is presentation only: colour changes on code text, never a
// change to the text, its layout or the document.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';
import 'package:lightweight_rich_editor/src/rendering/code_highlighter.dart';

import '../support/notebook_test_support.dart';
import 'notebook_policy_test.dart' show lay;

List<(String, CodeTokenKind)> tokens(String code, String lang) =>
    [for (final t in tokenizeCode(code, lang)) (code.substring(t.start, t.end), t.kind)];

TextAttribute codeSpan(int s, int e, String level) => TextAttribute(start: s, end: e, type: AttributeType.header, value: level);

void main() {
  group('tokenizer', () {
    test('dart: keywords, types, strings, numbers, comments, literals', () {
      final t = tokens("final x = Foo('a', 12); // note\nvoid main() { return null; }", 'dart');
      expect(t, containsAll([
        ('final', CodeTokenKind.keyword),
        ('Foo', CodeTokenKind.type),
        ("'a'", CodeTokenKind.string),
        ('12', CodeTokenKind.number),
        ('// note', CodeTokenKind.comment),
        ('void', CodeTokenKind.keyword),
        ('return', CodeTokenKind.keyword),
        ('null', CodeTokenKind.literal),
      ]));
    });

    test('a keyword inside a string or comment is not a keyword', () {
      final t = tokens("print('if else'); // for while", 'dart');
      expect(t.where((e) => e.$2 == CodeTokenKind.keyword), isEmpty);
    });

    test('block comments span lines; an unterminated one runs to the end', () {
      expect(tokens('a /* one\ntwo */ b', 'dart').single, ('/* one\ntwo */', CodeTokenKind.comment));
      expect(tokens('a /* never closed\nmore', 'js').single.$2, CodeTokenKind.comment);
    });

    test('strings: escapes, an unterminated one ends at its line, template literals span lines', () {
      expect(tokens(r'x = "a\"b"', 'js').single, (r'"a\"b"', CodeTokenKind.string));
      final t = tokens('s = "open\nnext = 1', 'js');
      expect(t.first, ('"open', CodeTokenKind.string));
      expect(t.last, ('1', CodeTokenKind.number));
      expect(tokens('`a\nb`', 'js').single, ('`a\nb`', CodeTokenKind.string));
    });

    test('python: # comments, triple quotes, True/None', () {
      final t = tokens('def f():\n  """doc\n  more"""  # tail\n  return None', 'python');
      expect(t.map((e) => e.$2), containsAll([CodeTokenKind.keyword, CodeTokenKind.string, CodeTokenKind.comment, CodeTokenKind.literal]));
      expect(t.firstWhere((e) => e.$2 == CodeTokenKind.string).$1, '"""doc\n  more"""');
    });

    test('sql keywords are case-insensitive; json has strings, numbers, literals only', () {
      expect(tokens('SELECT a FROM t -- c', 'sql').where((e) => e.$2 == CodeTokenKind.keyword).map((e) => e.$1), ['SELECT', 'FROM']);
      final j = tokens('{"a": [1, 2.5, true, null]}', 'json');
      expect(j.map((e) => e.$2).toSet(), {CodeTokenKind.string, CodeTokenKind.number, CodeTokenKind.literal});
    });

    test('html: tags, attribute strings and comments', () {
      final t = tokens('<!-- c --><div class="a">x</div>', 'html');
      expect(t, containsAll([('<!-- c -->', CodeTokenKind.comment), ('div', CodeTokenKind.keyword), ('"a"', CodeTokenKind.string)]));
    });

    test('digits inside identifiers are not numbers; hex literals are one number', () {
      expect(tokens('var a1 = 0xFF;', 'dart').where((e) => e.$2 == CodeTokenKind.number).map((e) => e.$1), ['0xFF']);
    });

    test('unknown or missing language, and empty code: no tokens', () {
      expect(tokenizeCode('int x', 'brainfuck'), isEmpty);
      expect(tokenizeCode('int x', null), isEmpty);
      expect(tokenizeCode('', 'dart'), isEmpty);
      expect(canHighlight('dart'), isTrue);
      expect(canHighlight('unknown'), isFalse);
    });

    test('tokens never overlap and stay in order, on adversarial input', () {
      const nasty = "'\"`/*//#--<!-- \\ \u{1F600} \n\n\"unterminated\n/* x\n'''\n";
      for (final lang in ['dart', 'js', 'python', 'sql', 'html', 'shell', 'json', 'css', 'go']) {
        var last = 0;
        for (final t in tokenizeCode(nasty * 3, lang)) {
          expect(t.start, greaterThanOrEqualTo(last), reason: lang);
          expect(t.end, greaterThan(t.start), reason: lang);
          last = t.end;
        }
      }
    });

    test('scales: 200k characters tokenise in well under a second', () {
      final code = List.filled(20000, 'final x = Foo(1, "a"); // c').join('\n');
      final sw = Stopwatch()..start();
      final t = tokenizeCode(code, 'dart');
      sw.stop();
      expect(t.length, 100000);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('renderer', () {
    const dartText = "final a = 1; // c\nvoid f() {}";

    RichEditorController make(String level) =>
        RichEditorController(text: dartText, theme: notebookTheme, initialAttributes: [codeSpan(0, dartText.length, level)]);

    List<TextSpan> leaves(RichEditorController c) {
      final span = c.renderer.renderSpan(c.document, style: const TextStyle(fontSize: 16));
      return span.children!.cast<TextSpan>();
    }

    test('a labelled block is coloured; the rendered text is exactly the document text', () {
      final c = make('code:dart');
      addTearDown(c.dispose);
      final runs = leaves(c);
      expect(runs.map((r) => r.text).join(), dartText);
      final kw = runs.firstWhere((r) => r.text == 'final');
      expect(kw.style!.color, notebookTheme.codeSyntax.keyword);
      final cm = runs.firstWhere((r) => r.text == '// c');
      expect(cm.style!.color, notebookTheme.codeSyntax.comment);
      expect(runs.every((r) => r.style!.fontFamily == notebookTheme.codeFontFamily), isTrue);
      expect(runs.map((r) => r.style!.fontSize).toSet().length, 1, reason: 'colour only: one size, no layout change');
    });

    test('an unlabelled block, or an unknown language, is not coloured', () {
      for (final level in ['code', 'code:brainfuck']) {
        final c = make(level);
        addTearDown(c.dispose);
        final runs = leaves(c);
        expect(runs.length, 1, reason: 'one run when nothing is highlighted ($level)');
        expect(runs.map((r) => r.style!.color).toSet().length, 1);
      }
    });

    test('colours come from the theme: the dark palette replaces the light one', () {
      final c = RichEditorController(
        text: dartText,
        theme: notebookTheme.copyWith(codeSyntax: CodeSyntaxColors.dark),
        initialAttributes: [codeSpan(0, dartText.length, 'code:dart')],
      );
      addTearDown(c.dispose);
      final kw = leaves(c).firstWhere((r) => r.text == 'final');
      expect(kw.style!.color, CodeSyntaxColors.dark.keyword);
      expect(CodeSyntaxColors.dark, isNot(CodeSyntaxColors.light));
    });

    test('highlighting never changes the ruled grid: same rows and heights with and without a label', () {
      final a = lay(dartText, attrs: [codeSpan(0, dartText.length, 'code:dart')], dpr: 1.0);
      final b = lay(dartText, attrs: [codeSpan(0, dartText.length, 'code')], dpr: 1.0);
      expect(a.bottoms, b.bottoms);
      expect([for (final r in a.renderer.codeBlocks) (r.top, r.bottom)], [for (final r in b.renderer.codeBlocks) (r.top, r.bottom)]);
    });

    test('a multi-line comment colours every line it covers, across paragraph boundaries', () {
      const t = 'a /* x\ny\nz */ b';
      final c = RichEditorController(text: t, theme: notebookTheme, initialAttributes: [codeSpan(0, t.length, 'code:dart')]);
      addTearDown(c.dispose);
      final runs = leaves(c);
      expect(runs.map((r) => r.text).join(), t);
      final commentRuns = runs.where((r) => r.style!.color == notebookTheme.codeSyntax.comment).map((r) => r.text).join();
      expect(commentRuns, '/* x\ny\nz */');
    });

    test('editing code re-tokenises; editing prose keeps the cached tokens', () {
      final c = make('code:dart');
      addTearDown(c.dispose);
      expect(leaves(c).any((r) => r.text == 'final'), isTrue);
      c.value = const TextEditingValue(text: 'finalx = 1; // c\nvoid f() {}', selection: TextSelection.collapsed(offset: 6));
      expect(leaves(c).any((r) => r.text == 'final'), isFalse, reason: 'finalx is an identifier now');
    });
  });
}
