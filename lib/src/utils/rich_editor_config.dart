import 'package:flutter/material.dart';

/// Configuration for the [RichTextEditor] and [RichTextEditingController].
///
/// This class handles both styling and behavioral settings.
class RichEditorConfig {
  // --- Styling: Typography ---
  final double fontSize;
  final double lineHeightMultiplier;

  // --- Styling: Colors ---
  final Color highlightColor;
  final Color linkColor;
  final Color codeBackgroundColor;
  final Color ruledLineColor;
  final Color marginLineColor;

  // --- Styling: Layout ---
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeftMarginOn;
  final double paddingLeftMarginOff;
  final double marginLineX;

  // --- Behavior ---
  final int maxHistoryLength;
  final bool enableStickyFormatting;

  const RichEditorConfig({
    this.fontSize = 18.0,
    this.lineHeightMultiplier = 1.5,
    this.highlightColor = const Color(0x99E1BEE7),
    this.linkColor = Colors.blue,
    this.codeBackgroundColor = const Color(0xFFF5F5F5),
    this.ruledLineColor = const Color(0x66607D8B),
    this.marginLineColor = const Color(0xCCFFCDD2),
    this.paddingTop = 12.0,
    this.paddingRight = 24.0,
    this.paddingBottom = 40.0,
    this.paddingLeftMarginOn = 58.0,
    this.paddingLeftMarginOff = 24.0,
    this.marginLineX = 44.0,
    this.maxHistoryLength = 100,
    this.enableStickyFormatting = true,
  });

  /// Standard configuration with default values.
  static const RichEditorConfig standard = RichEditorConfig();

  /// Calculates the effective line height.
  double get lineHeight => fontSize * lineHeightMultiplier;

  /// Returns a copy of this configuration with the given fields replaced.
  RichEditorConfig copyWith({
    double? fontSize,
    double? lineHeightMultiplier,
    Color? highlightColor,
    Color? linkColor,
    Color? codeBackgroundColor,
    Color? ruledLineColor,
    Color? marginLineColor,
    double? paddingTop,
    double? paddingRight,
    double? paddingBottom,
    double? paddingLeftMarginOn,
    double? paddingLeftMarginOff,
    double? marginLineX,
    int? maxHistoryLength,
    bool? enableStickyFormatting,
  }) {
    return RichEditorConfig(
      fontSize: fontSize ?? this.fontSize,
      lineHeightMultiplier: lineHeightMultiplier ?? this.lineHeightMultiplier,
      highlightColor: highlightColor ?? this.highlightColor,
      linkColor: linkColor ?? this.linkColor,
      codeBackgroundColor: codeBackgroundColor ?? this.codeBackgroundColor,
      ruledLineColor: ruledLineColor ?? this.ruledLineColor,
      marginLineColor: marginLineColor ?? this.marginLineColor,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingRight: paddingRight ?? this.paddingRight,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      paddingLeftMarginOn: paddingLeftMarginOn ?? this.paddingLeftMarginOn,
      paddingLeftMarginOff: paddingLeftMarginOff ?? this.paddingLeftMarginOff,
      marginLineX: marginLineX ?? this.marginLineX,
      maxHistoryLength: maxHistoryLength ?? this.maxHistoryLength,
      enableStickyFormatting: enableStickyFormatting ?? this.enableStickyFormatting,
    );
  }
}
