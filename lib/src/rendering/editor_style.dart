import 'package:flutter/material.dart';

/// Layout and background painting configuration for [RichTextEditor].
///
/// This holds parameters for ruled lines, margins, and editor padding.
/// Deliberately separate from [RichTextRenderTheme], which handles
/// text-level styling.
@immutable
class RichEditorStyle {
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeftMarginOn;
  final double paddingLeftMarginOff;
  final double marginLineX;

  final Color ruledLineColor;
  final Color marginLineColor;

  const RichEditorStyle({
    this.paddingTop = 12.0,
    this.paddingRight = 24.0,
    this.paddingBottom = 40.0,
    this.paddingLeftMarginOn = 58.0,
    this.paddingLeftMarginOff = 24.0,
    this.marginLineX = 44.0,
    this.ruledLineColor = const Color(0x66607D8B),
    this.marginLineColor = const Color(0xCCFFCDD2),
  });

  static const standard = RichEditorStyle();

  /// Alias for [marginLineColor] — `RuledLinesPainter` takes a
  /// `marginColor` parameter by that name, so this exists to match its
  /// call site without renaming the field everywhere else.
  Color get marginColor => marginLineColor;

  RichEditorStyle copyWith({
    double? paddingTop,
    double? paddingRight,
    double? paddingBottom,
    double? paddingLeftMarginOn,
    double? paddingLeftMarginOff,
    double? marginLineX,
    Color? ruledLineColor,
    Color? marginLineColor,
  }) {
    return RichEditorStyle(
      paddingTop: paddingTop ?? this.paddingTop,
      paddingRight: paddingRight ?? this.paddingRight,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      paddingLeftMarginOn: paddingLeftMarginOn ?? this.paddingLeftMarginOn,
      paddingLeftMarginOff: paddingLeftMarginOff ?? this.paddingLeftMarginOff,
      marginLineX: marginLineX ?? this.marginLineX,
      ruledLineColor: ruledLineColor ?? this.ruledLineColor,
      marginLineColor: marginLineColor ?? this.marginLineColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RichEditorStyle &&
        other.paddingTop == paddingTop &&
        other.paddingRight == paddingRight &&
        other.paddingBottom == paddingBottom &&
        other.paddingLeftMarginOn == paddingLeftMarginOn &&
        other.paddingLeftMarginOff == paddingLeftMarginOff &&
        other.marginLineX == marginLineX &&
        other.ruledLineColor == ruledLineColor &&
        other.marginLineColor == marginLineColor;
  }

  @override
  int get hashCode => Object.hash(
        paddingTop,
        paddingRight,
        paddingBottom,
        paddingLeftMarginOn,
        paddingLeftMarginOff,
        marginLineX,
        ruledLineColor,
        marginLineColor,
      );
}
