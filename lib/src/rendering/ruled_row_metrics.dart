import 'package:flutter/painting.dart';

import 'render_theme.dart';

/// The single source of truth for the notebook's ruled grid, for one
/// effective `(theme, TextScaler, devicePixelRatio)` combination.
///
/// Everything that must agree about row geometry reads it from here: the
/// renderer (per-span `TextStyle.height`), the editor (strut, fallback rule
/// spacing) and the painter (interior rules of multi-row lines). A new
/// instance is built whenever any of those inputs change, so no cached
/// measurement can outlive the scale it was taken at.
///
/// Policy:
///  * **Inline text** (bold, italic, colour, a custom `size` span, ...) is
///    *fitted to one row*: [fitInlineFontSize] shrinks a size whose natural
///    glyph height would exceed `pitch × theme.rowFill`, so no inline span
///    can ever make a row taller than [pitch].
///  * **Paragraph headers** are *never shrunk*. [rowsForParagraph] returns the
///    minimum whole number of rows their real glyph metrics need, and their
///    line boxes are exactly that many pitches tall — so every line bottom
///    stays a whole multiple of [pitch].
///
/// Both decisions come from measured `TextPainter` metrics at the *scaled*
/// font size — never from a size→rows table.
class RuledRowMetrics {
  RuledRowMetrics({
    required this.theme,
    this.textScaler = TextScaler.noScaling,
    this.devicePixelRatio = 1.0,
    this.baseFontFamily,
  }) : pitch = _snapToPixels(_scaledLineHeight(theme, textScaler));

  final RichTextRenderTheme theme;
  final TextScaler textScaler;
  final double devicePixelRatio;

  /// Font family of the editor's base style; `null` means the default font.
  final String? baseFontFamily;

  /// The height of one ruled row in logical pixels, *after* system text
  /// scaling and rounded to a whole logical pixel (what the engine lays rows
  /// out at), so every row and every multi-row line is an exact multiple of
  /// it. [devicePixelRatio] does not change it; the painter uses the ratio
  /// only to place the 1px rule strokes on physical pixels.
  final double pitch;

  /// Largest natural glyph height an inline span (or a one-row header) may
  /// have and still fit its row with clearance.
  double get maxNaturalHeight => pitch * theme.rowFill;

  /// The same limit for a paragraph header (see [RichTextRenderTheme.headerRowFill]).
  double get maxHeaderNaturalHeight => pitch * theme.headerRowFill;

  /// `TextStyle.height` that makes a line of nominal size [fontSize] exactly
  /// [rows] pitches tall. Flutter applies `height` to the *scaled* font size,
  /// hence the [textScaler] in the denominator.
  double heightMultiplier(double fontSize, {int rows = 1}) =>
      rows * pitch / textScaler.scale(fontSize);

  final Map<String, double> _naturalCache = {};
  final Map<String, double> _maxInlineCache = {};

  /// The measured natural line height of a glyph run at the *scaled* size
  /// (what will actually render), or `null` if it can't be measured.
  double? naturalHeight(
    double fontSize,
    FontWeight weight,
    bool italic,
    String? family,
  ) {
    final scaled = textScaler.scale(fontSize);
    final key = '$scaled|${weight.value}|$italic|$family';
    final cached = _naturalCache[key];
    if (cached != null) return cached;
    try {
      final probe = TextPainter(
        text: TextSpan(
          text: 'Ág', // tall ascender + descender, a representative worst case
          style: TextStyle(
            fontSize: scaled,
            fontWeight: weight,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontFamily: family,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lines = probe.computeLineMetrics();
      probe.dispose();
      if (lines.length != 1) return null;
      final natural = lines.single.height;
      if (!natural.isFinite || natural <= 0) return null;
      _naturalCache[key] = natural;
      return natural;
    } catch (_) {
      return null;
    }
  }

  bool _fits(double fontSize, FontWeight weight, bool italic, String? family) {
    final natural = naturalHeight(fontSize, weight, italic, family);
    // An unmeasurable size is treated as fitting: never take the whole
    // document's layout down over a failed probe.
    return natural == null || natural <= maxNaturalHeight;
  }

  /// The largest whole nominal inline font size (≥ 1) whose natural height
  /// still fits one row for this weight/style/family. This is the ceiling the
  /// toolbar should expose.
  double maxInlineFontSize({
    FontWeight weight = FontWeight.normal,
    bool italic = false,
    String? family,
  }) {
    final fam = family ?? baseFontFamily;
    final key = '${weight.value}|$italic|$fam';
    final cached = _maxInlineCache[key];
    if (cached != null) return cached;
    var lo = 1; // assumed to fit
    var hi = 512; // assumed not to fit
    if (_fits(hi.toDouble(), weight, italic, fam)) {
      lo = hi;
    } else {
      while (hi - lo > 1) {
        final mid = (lo + hi) >> 1;
        if (_fits(mid.toDouble(), weight, italic, fam)) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
    }
    return _maxInlineCache[key] = lo.toDouble();
  }

  /// [fontSize] itself if it fits one row, otherwise the largest size that
  /// does. Inline formatting never grows a row.
  double fitInlineFontSize(
    double fontSize,
    FontWeight weight,
    bool italic, {
    String? family,
  }) {
    if (!fontSize.isFinite || fontSize <= 0) return theme.baseFontSize;
    final fam = family ?? baseFontFamily;
    if (_fits(fontSize, weight, italic, fam)) return fontSize;
    final max = maxInlineFontSize(weight: weight, italic: italic, family: fam);
    return fontSize < max ? fontSize : max;
  }

  /// The minimum whole number of rows a paragraph-level header of nominal
  /// [fontSize] needs, from its measured natural height. Headers are never
  /// shrunk; they take as many rows as they need.
  int rowsForParagraph(double fontSize, FontWeight weight) {
    final natural = naturalHeight(fontSize, weight, false, baseFontFamily);
    if (natural == null || maxHeaderNaturalHeight <= 0) return 1;
    final rows = (natural / maxHeaderNaturalHeight).ceil();
    return rows < 1 ? 1 : rows;
  }

  /// Whether every header level (h1–h3) fits a single row at this scale, i.e.
  /// the whole document is made of exactly-one-pitch lines (the Notebook
  /// policy). The editor then forces the strut height so a line mixing
  /// fallback fonts (CJK, emoji, monospace) can never grow past one row: each
  /// font splits a forced `TextStyle.height` into ascent/descent in its own
  /// proportion, and the line takes the max of each, which measured up to a
  /// pixel taller than the pitch.
  bool get allHeadersFitOneRow => _allHeadersFitOneRow ??=
      rowsForParagraph(theme.h1FontSize, FontWeight.bold) == 1 &&
      rowsForParagraph(theme.h2FontSize, FontWeight.bold) == 1 &&
      rowsForParagraph(theme.h3FontSize, FontWeight.bold) == 1;
  bool? _allHeadersFitOneRow;

  /// The row height after text scaling, defined by how the BODY text scales:
  /// `lineHeight × (scaled base size / base size)`.
  ///
  /// For a linear scaler that is exactly `textScaler.scale(lineHeight)`. A
  /// non-linear one (Android 14+ system font scaling shrinks the growth of
  /// larger sizes: at font scale 2.0 a 16sp run becomes 28 but 30sp only 38)
  /// would make `scale(lineHeight)` too small for the text it has to hold —
  /// measured on a device, it pushed H1/H2 onto two rows. Anchoring the pitch
  /// to the body text keeps the row/body-text ratio constant at every scale,
  /// and since such curves never grow a larger size faster than a smaller one,
  /// whatever fits one row with a linear scaler still fits with them.
  static double _scaledLineHeight(RichTextRenderTheme theme, TextScaler scaler) {
    final base = theme.baseFontSize;
    if (!base.isFinite || base <= 0) return scaler.scale(theme.lineHeight);
    return theme.lineHeight * scaler.scale(base) / base;
  }

  // Snapped to a whole *logical* pixel, not a physical one: the engine rounds
  // paragraph line heights to integer logical pixels (measured: a requested
  // 14.909px row lays out as 15.0px at devicePixelRatio 2.75), so any other
  // pitch would disagree with the rows actually laid out, drifting the rules
  // off the text one row at a time.
  static double _snapToPixels(double value) {
    if (!value.isFinite || value <= 0) return 1.0;
    final snapped = value.roundToDouble();
    return snapped < 1.0 ? 1.0 : snapped;
  }
}
