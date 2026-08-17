import 'package:flutter/material.dart';

/// Visual parameters [TextSpanRenderer] resolves attributes into: fonts,
/// sizes, colors.
///
/// Deliberately separate from *editing* configuration (undo history
/// length, whether sticky formatting is enabled) — the old
/// `RichEditorConfig` mixed both together, but they change for different
/// reasons and are read by different components. History length belongs
/// with `HistoryManager`; this belongs with the renderer.
@immutable
class RichTextRenderTheme {
  final double baseFontSize;

  /// Target line height in logical pixels. Converted to Flutter's
  /// height-multiplier convention (`height = lineHeight / fontSize`) per
  /// segment, so line spacing stays visually constant across mixed font
  /// sizes (e.g. a header line next to body text) — same approach the
  /// original controller used.
  final double lineHeight;

  final double h1FontSize;
  final double h2FontSize;

  final Color highlightColor;
  final Color codeBackgroundColor;
  final Color linkColor;
  final String codeFontFamily;

  /// Background color for the current find-and-replace match — see
  /// `TextSpanRenderer.renderSpan`'s `matchHighlightRange`. Deliberately
  /// distinct from [highlightColor] (a different hue, not just a
  /// different opacity of the same one) so the current search match is
  /// visually unmistakable even on text that already has the `highlight`
  /// attribute applied.
  final Color matchHighlightColor;

  /// Background color for every *other* search match — see
  /// `TextSpanRenderer.renderSpan`'s `allMatchesRanges`. A paler variant
  /// of [matchHighlightColor] by default (same hue, so "these are all
  /// search matches" still reads as one family), so the *current* match
  /// stays the one that visually pops.
  final Color otherMatchesHighlightColor;

  /// Color applied to a literal list prefix (`'- '`, `'3. '`, etc.) at
  /// the start of a paragraph — see `TextSpanRenderer._listPrefixStyle`.
  /// Purely presentational: the prefix is ordinary document text styled
  /// differently, not a generated marker, so this only ever affects
  /// color/weight, never what text exists or how long it is.
  final Color listMarkerColor;

  const RichTextRenderTheme({
    this.baseFontSize = 16.0,
    this.lineHeight = 24.0,
    this.h1FontSize = 28.0,
    this.h2FontSize = 22.0,
    this.highlightColor = const Color(0x66FFEB3B),
    this.codeBackgroundColor = const Color(0x1F000000),
    this.linkColor = const Color(0xFF1A73E8),
    this.codeFontFamily = 'monospace',
    this.matchHighlightColor = const Color(0xFFFFA726),
    this.otherMatchesHighlightColor = const Color(0x66FFA726),
    this.listMarkerColor = const Color(0xFF757575),
  });

  static const standard = RichTextRenderTheme();

  RichTextRenderTheme copyWith({
    double? baseFontSize,
    double? lineHeight,
    double? h1FontSize,
    double? h2FontSize,
    Color? highlightColor,
    Color? codeBackgroundColor,
    Color? linkColor,
    String? codeFontFamily,
    Color? matchHighlightColor,
    Color? otherMatchesHighlightColor,
    Color? listMarkerColor,
  }) {
    return RichTextRenderTheme(
      baseFontSize: baseFontSize ?? this.baseFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      h1FontSize: h1FontSize ?? this.h1FontSize,
      h2FontSize: h2FontSize ?? this.h2FontSize,
      highlightColor: highlightColor ?? this.highlightColor,
      codeBackgroundColor: codeBackgroundColor ?? this.codeBackgroundColor,
      linkColor: linkColor ?? this.linkColor,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      matchHighlightColor: matchHighlightColor ?? this.matchHighlightColor,
      otherMatchesHighlightColor: otherMatchesHighlightColor ?? this.otherMatchesHighlightColor,
      listMarkerColor: listMarkerColor ?? this.listMarkerColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RichTextRenderTheme &&
        other.baseFontSize == baseFontSize &&
        other.lineHeight == lineHeight &&
        other.h1FontSize == h1FontSize &&
        other.h2FontSize == h2FontSize &&
        other.highlightColor == highlightColor &&
        other.codeBackgroundColor == codeBackgroundColor &&
        other.linkColor == linkColor &&
        other.codeFontFamily == codeFontFamily &&
        other.matchHighlightColor == matchHighlightColor &&
        other.otherMatchesHighlightColor == otherMatchesHighlightColor &&
        other.listMarkerColor == listMarkerColor;
  }

  @override
  int get hashCode => Object.hash(
    baseFontSize,
    lineHeight,
    h1FontSize,
    h2FontSize,
    highlightColor,
    codeBackgroundColor,
    linkColor,
    codeFontFamily,
    matchHighlightColor,
    otherMatchesHighlightColor,
    listMarkerColor,
  );
}