import 'package:flutter/material.dart';

import 'code_highlighter.dart' show CodeSyntaxColors;

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

  /// Color for plain, unattributed text — the base every other color
  /// resolution (an explicit [AttributeType.color] span, a link) falls
  /// back to. Also the base for the ruled-editor's TextField `style`
  /// itself, so it's the one color a host must theme to support e.g.
  /// dark mode; every other themed color (link, highlight, code
  /// background) already lives here too.
  final Color textColor;

  /// Target line height in logical pixels. Converted to Flutter's
  /// height-multiplier convention (`height = lineHeight / fontSize`) per
  /// segment, so line spacing stays visually constant across mixed font
  /// sizes (e.g. a header line next to body text) — same approach the
  /// original controller used.
  final double lineHeight;

  /// Fraction of one ruled row that a glyph run's natural height may occupy
  /// before it no longer counts as fitting. Inline spans above it are shrunk
  /// to fit one row; headers above it take additional whole rows. Leaves the
  /// rest of the row as clearance around the glyphs.
  final double rowFill;

  /// Like [rowFill], but for paragraph headers. Higher by default: a heading
  /// only sits on its ruled line when it fits a single row (a multi-row line
  /// box cannot push its glyphs down to the bottom rule — the baseline lands
  /// a fixed fraction of the *whole* box above it), so headers may use almost
  /// the entire row before they are given a second one.
  final double headerRowFill;

  final double h1FontSize;
  final double h2FontSize;
  final double h3FontSize;

  final Color highlightColor;
  final Color codeBackgroundColor;
  final Color linkColor;
  final String codeFontFamily;

  /// Token colours for code blocks that carry a language label this package can
  /// highlight. Pass [CodeSyntaxColors.dark] on a dark code background.
  final CodeSyntaxColors codeSyntax;

  /// Background color for the current find-and-replace match.
  /// Deliberately a different hue from [highlightColor], not just a
  /// different opacity, so it stays unmistakable on already-highlighted
  /// text.
  final Color matchHighlightColor;

  /// Background color for every *other* search match — a paler variant
  /// of [matchHighlightColor] by default, so the current match still
  /// stands out.
  final Color otherMatchesHighlightColor;

  /// Color applied to a literal list prefix (`'- '`, `'3. '`, etc.) at
  /// the start of a paragraph.
  final Color listMarkerColor;

  const RichTextRenderTheme({
    this.baseFontSize = 16.0,
    this.textColor = const Color(0xFF000000),
    this.lineHeight = 24.0,
    this.rowFill = 0.9,
    this.headerRowFill = 0.98,
    this.h1FontSize = 28.0,
    this.h2FontSize = 22.0,
    this.h3FontSize = 18.0,
    this.highlightColor = const Color(0x66FFEB3B),
    this.codeBackgroundColor = const Color(0x1F000000),
    this.linkColor = const Color(0xFF1A73E8),
    this.codeFontFamily = 'monospace',
    this.codeSyntax = CodeSyntaxColors.light,
    this.matchHighlightColor = const Color(0xFFFFA726),
    this.otherMatchesHighlightColor = const Color(0x66FFA726),
    this.listMarkerColor = const Color(0xFF757575),
  });

  static const standard = RichTextRenderTheme();

  RichTextRenderTheme copyWith({
    double? baseFontSize,
    Color? textColor,
    double? lineHeight,
    double? rowFill,
    double? headerRowFill,
    double? h1FontSize,
    double? h2FontSize,
    double? h3FontSize,
    Color? highlightColor,
    Color? codeBackgroundColor,
    Color? linkColor,
    String? codeFontFamily,
    CodeSyntaxColors? codeSyntax,
    Color? matchHighlightColor,
    Color? otherMatchesHighlightColor,
    Color? listMarkerColor,
  }) {
    return RichTextRenderTheme(
      baseFontSize: baseFontSize ?? this.baseFontSize,
      textColor: textColor ?? this.textColor,
      lineHeight: lineHeight ?? this.lineHeight,
      rowFill: rowFill ?? this.rowFill,
      headerRowFill: headerRowFill ?? this.headerRowFill,
      h1FontSize: h1FontSize ?? this.h1FontSize,
      h2FontSize: h2FontSize ?? this.h2FontSize,
      h3FontSize: h3FontSize ?? this.h3FontSize,
      highlightColor: highlightColor ?? this.highlightColor,
      codeBackgroundColor: codeBackgroundColor ?? this.codeBackgroundColor,
      linkColor: linkColor ?? this.linkColor,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      codeSyntax: codeSyntax ?? this.codeSyntax,
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
        other.textColor == textColor &&
        other.lineHeight == lineHeight &&
        other.rowFill == rowFill &&
        other.headerRowFill == headerRowFill &&
        other.h1FontSize == h1FontSize &&
        other.h2FontSize == h2FontSize &&
        other.h3FontSize == h3FontSize &&
        other.highlightColor == highlightColor &&
        other.codeBackgroundColor == codeBackgroundColor &&
        other.linkColor == linkColor &&
        other.codeFontFamily == codeFontFamily &&
        other.codeSyntax == codeSyntax &&
        other.matchHighlightColor == matchHighlightColor &&
        other.otherMatchesHighlightColor == otherMatchesHighlightColor &&
        other.listMarkerColor == listMarkerColor;
  }

  @override
  int get hashCode => Object.hash(
    baseFontSize,
    textColor,
    lineHeight,
    rowFill,
    headerRowFill,
    h1FontSize,
    h2FontSize,
    h3FontSize,
    highlightColor,
    codeBackgroundColor,
    linkColor,
    codeFontFamily,
    codeSyntax,
    matchHighlightColor,
    otherMatchesHighlightColor,
    listMarkerColor,
  );
}