/// Matches a paragraph whose *entire* text is three or more hyphens (the
/// standard Markdown thematic-break convention) — e.g. `'---'`,
/// `'-----'`. Unlike [listPrefixPattern] in `list_prefix.dart` (a prefix
/// followed by content), this must match the whole paragraph: a
/// horizontal rule stands alone on its own line, nothing else on it. A
/// bare hyphen run never collides with the bullet prefix pattern either
/// way — that requires a hyphen *followed by a space* (`'- '`), which
/// `'---'` never has.
///
/// Purely derived from literal text, same "no stored field" discipline
/// `listPrefixLength` already follows — see `ParagraphRecord`'s doc
/// comment on why block-level state only gets a stored field when
/// there's truly no textual representation available. A user (or an
/// import) can type any run length they like; whatever's actually there
/// is what gets styled, nothing is rewritten or canonicalized.
final RegExp horizontalRulePattern = RegExp(r'^-{3,}$');

/// Whether the paragraph text `text.substring(start, end)` (its own
/// content, no trailing newline) is a horizontal rule line.
bool isHorizontalRuleLine(String text, int start, int end) {
  if (end <= start) return false;
  return horizontalRulePattern.hasMatch(text.substring(start, end));
}
