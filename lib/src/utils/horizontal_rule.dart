/// Matches a paragraph whose entire text is three or more hyphens (the
/// Markdown thematic-break convention), e.g. `'---'`, `'-----'`.
final RegExp horizontalRulePattern = RegExp(r'^-{3,}$');

/// Whether `text.substring(start, end)` is a horizontal rule line.
bool isHorizontalRuleLine(String text, int start, int end) {
  if (end <= start) return false;
  return horizontalRulePattern.hasMatch(text.substring(start, end));
}
