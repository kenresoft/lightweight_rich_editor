// ignore_for_file: avoid_print
//
// Caching contract of the ruled-grid pipeline on a large Notebook-configured
// document: metrics / span / line-bottom caches are hit when nothing relevant
// changed, keyed by text scale and pixel ratio, and a formatting change costs
// one document pass — not a metric re-measurement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

import '../support/notebook_test_support.dart';

const _style = TextStyle(fontFamily: 'Roboto');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);

  RichEditorController bigDoc() {
    final b = StringBuffer();
    final attrs = <TextAttribute>[];
    for (var p = 0; p < 1500; p++) {
      if (p > 0) b.write('\n');
      final s = b.length;
      b.write('Paragraph $p: the quick brown fox jumps over the lazy dog near the riverbank.');
      if (p % 5 == 0) attrs.add(TextAttribute(start: s + 12, end: s + 20, type: AttributeType.size, value: 22));
      if (p % 7 == 0) attrs.add(TextAttribute(start: s + 21, end: s + 30, type: AttributeType.bold));
      if (p % 50 == 0) attrs.add(TextAttribute(start: s, end: b.length, type: AttributeType.header, value: 'h2'));
    }
    return RichEditorController(text: b.toString(), theme: notebookTheme, initialAttributes: attrs);
  }

  const behavior = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.proportional);

  test('metrics, span and line-bottom caches are hit unless an input really changed', () {
    final c = bigDoc();
    addTearDown(c.dispose);
    final r = c.renderer;
    final scaler = TextScaler.linear(1.3);
    final m = r.rowMetrics(textScaler: scaler, devicePixelRatio: 2.75, style: _style);
    final rowHeight = m.heightMultiplier(16);
    final style = _style.copyWith(fontSize: 16, height: rowHeight, leadingDistribution: TextLeadingDistribution.proportional);
    final strut = StrutStyle(fontFamily: 'Roboto', fontSize: 16, height: rowHeight, leadingDistribution: TextLeadingDistribution.proportional, forceStrutHeight: true, leading: 0);

    List<double> bottoms({TextScaler? s, double dpr = 2.75}) => r.lineBottomOffsets(
      c.document,
      maxWidth: 318,
      style: style,
      strutStyle: strut,
      textHeightBehavior: behavior,
      textScaler: s ?? scaler,
      devicePixelRatio: dpr,
    );
    TextSpan span({TextScaler? s, double dpr = 2.75}) =>
        r.renderSpan(c.document, style: style, textScaler: s ?? scaler, devicePixelRatio: dpr);

    final cold = Stopwatch()..start();
    final b1 = bottoms();
    final s1 = span();
    cold.stop();

    // Equal-valued (not identical) scaler objects share everything.
    expect(identical(bottoms(s: TextScaler.linear(1.3)), b1), isTrue);
    expect(identical(span(s: TextScaler.linear(1.3)), s1), isTrue);
    expect(identical(r.rowMetrics(textScaler: TextScaler.linear(1.3), devicePixelRatio: 2.75, style: _style), m), isTrue);

    // A selection-only change touches nothing the pipeline keys on.
    c.selection = const TextSelection(baseOffset: 10, extentOffset: 40);
    c.selection = const TextSelection.collapsed(offset: 500);
    expect(identical(bottoms(), b1), isTrue);
    expect(identical(span(), s1), isTrue);

    // Text scale and pixel ratio are part of every key.
    expect(identical(bottoms(s: TextScaler.linear(1.4)), b1), isFalse);
    expect(identical(bottoms(dpr: 3.0), b1), isFalse);
    expect(identical(span(s: TextScaler.linear(2.0)), s1), isFalse);
    expect(r.rowMetrics(textScaler: TextScaler.linear(2.0), devicePixelRatio: 2.75, style: _style).pitch, 60);
    expect(r.rowMetrics(textScaler: TextScaler.linear(1.3), devicePixelRatio: 2.75, style: _style).pitch, 39);

    // A theme change drops the metrics (their pitch/fit were measured against the old theme).
    final m2 = r.rowMetrics(textScaler: scaler, devicePixelRatio: 2.75, style: _style);
    r.theme = r.theme.copyWith(lineHeight: 28);
    expect(identical(r.rowMetrics(textScaler: scaler, devicePixelRatio: 2.75, style: _style), m2), isFalse);
    r.theme = notebookTheme;

    print('cold span+lineBottoms for ${c.document.text.length} chars: ${cold.elapsedMilliseconds}ms');
  });

  test('repeated formatting changes re-lay the document once each and never re-measure the metrics', () {
    final c = bigDoc();
    addTearDown(c.dispose);
    final r = c.renderer;
    final m = r.rowMetrics(textScaler: TextScaler.linear(1.0), style: _style);
    r.activeRowMetrics = m;
    final rowHeight = m.heightMultiplier(16);
    final style = _style.copyWith(fontSize: 16, height: rowHeight, leadingDistribution: TextLeadingDistribution.proportional);
    final strut = StrutStyle(fontFamily: 'Roboto', fontSize: 16, height: rowHeight, leadingDistribution: TextLeadingDistribution.proportional, forceStrutHeight: true, leading: 0);

    // Warm the ceiling caches for every face the toggles below will visit.
    final ceiling = m.maxInlineFontSize();
    final ceilingBold = m.maxInlineFontSize(weight: FontWeight.bold);
    final probe = Stopwatch()..start();
    for (var i = 0; i < 5000; i++) {
      m.maxInlineFontSize();
      m.maxInlineFontSize(weight: FontWeight.bold);
      m.fitInlineFontSize(400, FontWeight.normal, false, family: 'Roboto');
    }
    probe.stop();
    print('15,000 cached ceiling/fit lookups: ${probe.elapsedMilliseconds}ms');
    expect(probe.elapsedMilliseconds, lessThan(500), reason: 'ceiling lookups must be cache hits, not TextPainter probes');

    final at = c.document.text.indexOf('Paragraph 1:') + 13;
    final word = TextSelection(baseOffset: at, extentOffset: at + 7);
    final perChange = <int>[];
    var previous = c.document.attributeStore.revision;
    var changed = 0;
    for (var i = 0; i < 30; i++) {
      c.selection = word;
      (i.isEven ? c.increaseFontSize : c.decreaseFontSize)();
      if (i % 3 == 0) c.toggleBold();
      if (c.document.attributeStore.revision != previous) changed++;
      previous = c.document.attributeStore.revision;
      final sw = Stopwatch()..start();
      final b = r.lineBottomOffsets(c.document, maxWidth: 318, style: style, strutStyle: strut, textHeightBehavior: behavior);
      sw.stop();
      perChange.add(sw.elapsedMilliseconds);
      expect(b.length, greaterThanOrEqualTo(1500));
      // Same metrics instance all the way: nothing was re-measured or rebuilt.
      expect(identical(r.rowMetrics(textScaler: TextScaler.noScaling, style: _style), m), isTrue);
    }
    expect(changed, greaterThan(15), reason: "the loop must really mutate the document");
    expect(m.maxInlineFontSize(), ceiling);
    expect(m.maxInlineFontSize(weight: FontWeight.bold), ceilingBold);
    final sorted = [...perChange]..sort();
    print('formatting change → renderSpan + line layout over ${c.document.text.length} chars: '
        'median ${sorted[sorted.length ~/ 2]}ms, max ${sorted.last}ms');
    expect(sorted.last, lessThan(3000));
  });
}
