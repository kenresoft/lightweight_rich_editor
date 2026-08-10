import 'clamp_int.dart';

/// Matches a literal list-style prefix anchored at the very start of the
/// string it's tested against: optional leading spaces/tabs (nesting
/// indentation), then `'- '`, `'* '`, `'+ '` (bullets) or a
/// one-to-nine-digit `'N. '` (numbered). Always used via
/// [RegExp.matchAsPrefix], so it only ever matches at position 0 of
/// whatever substring is passed in — callers slice to the position they
/// care about first.
///
/// The leading-whitespace group is what makes a nested list line
/// (`'  - sub item'`) recognizable as a list line at all. That
/// indentation is never generated here — it's real text already sitting
/// in the document, carried over verbatim from wherever it came from
/// (typed, or preserved as-is from a Markdown import that indented a
/// nested item with leading spaces; see the removal notes on
/// `AttributeType` for why this library never strips or rewrites list
/// text). This pattern just widens what counts as "a list prefix" to
/// recognize indentation that was already there.
///
/// This is a purely textual pattern with no relationship to
/// `AttributeType` — list "formatting" is literal characters a user (or
/// an import) typed, detected and styled presentationally wherever
/// they're found. Virtual, non-document marker characters broke
/// `RenderEditable`'s caret math; literal text detected at render/edit
/// time can't do that — there's nothing here that isn't already in
/// `document.text`.
final RegExp listPrefixPattern = RegExp(r'^[ \t]*(?:[-*+] |\d{1,9}\. )');

/// Length of the list-style prefix (if any, indentation included)
/// starting at `paragraphStart` in `text`, or 0 if the paragraph doesn't
/// start with one.
///
/// Only looks at a small fixed window right after `paragraphStart` —
/// list prefixes, even indented ones, are short by construction — so
/// this is O(1) regardless of document size. Safe to call once per
/// paragraph during a render sweep or a single keypress without
/// reintroducing the O(document length)-per-call scans the old
/// list-attribute handling did.
int listPrefixLength(String text, int paragraphStart) {
  final windowEnd = clampInt(paragraphStart + 24, paragraphStart, text.length);
  final window = text.substring(paragraphStart, windowEnd);
  final match = listPrefixPattern.matchAsPrefix(window);
  return match?.end ?? 0;
}

/// The literal prefix text that continues this list on the next line
/// after Enter, indentation included: unchanged for bullet markers
/// (`'  - '` stays `'  - '`), incremented for a numbered marker
/// (`'  3. '` -> `'  4. '`) — nested/indented numbered items keep their
/// indentation while still counting up correctly.
String nextListPrefix(String prefix) {
  final numbered = RegExp(r'^([ \t]*)(\d+)(\. )$').firstMatch(prefix);
  if (numbered == null) return prefix;
  final leading = numbered.group(1)!;
  final n = int.parse(numbered.group(2)!);
  return '$leading${n + 1}${numbered.group(3)}';
}