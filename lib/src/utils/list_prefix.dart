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
/// A bullet marker may optionally be followed by a checkbox segment
/// (`'[ ] '`/`'[x] '`/`'[X] '`) — standard GFM task-list syntax, and the
/// same literal-text convention as the bullet/number itself: `'- [ ] '`
/// is real, individually-editable characters, not stored state (see
/// [checkboxStateOfPrefix]). Numbered items never get a checkbox
/// segment — task lists aren't ordered in any convention this library
/// follows.
///
/// This is a purely textual pattern with no relationship to
/// `AttributeType` — list "formatting" is literal characters a user (or
/// an import) typed, detected and styled presentationally wherever
/// they're found. Virtual, non-document marker characters broke
/// `RenderEditable`'s caret math; literal text detected at render/edit
/// time can't do that — there's nothing here that isn't already in
/// `document.text`.
final RegExp listPrefixPattern = RegExp(r'^[ \t]*(?:[-*+] (?:\[[ xX]\] )?|\d{1,9}\. )');

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
/// after Enter, indentation included: unchanged for a plain bullet
/// marker (`'  - '` stays `'  - '`), incremented for a numbered marker
/// (`'  3. '` -> `'  4. '`) — nested/indented numbered items keep their
/// indentation while still counting up correctly. A checkbox segment
/// resets to unchecked (`'- [x] '` -> `'- [ ] '`) rather than carrying
/// the previous item's checked state onto a new, not-yet-done item.
String nextListPrefix(String prefix) {
  final numbered = RegExp(r'^([ \t]*)(\d+)(\. )$').firstMatch(prefix);
  if (numbered != null) {
    final leading = numbered.group(1)!;
    final n = int.parse(numbered.group(2)!);
    return '$leading${n + 1}${numbered.group(3)}';
  }
  return prefix.replaceFirst(RegExp(r'\[[xX]\] $'), '[ ] ');
}

/// Which kind of list a matched prefix represents. Not a stored
/// document property — see `EditingEngine.listToggleEdit`'s doc comment
/// for why list-ness is deliberately never anything but this pattern
/// matched against real text, unlike header (`ParagraphIndex.headerLevel`),
/// which has no textual representation at all and genuinely needs to be
/// stored.
enum ParagraphListType { bullet, numbered }

/// The [ParagraphListType] a matched `prefix` (as returned by
/// [listPrefixPattern]/[listPrefixLength]) represents, or `null` if
/// `prefix` doesn't actually match the pattern (defensive — every real
/// caller only ever passes a string [listPrefixLength] already
/// confirmed matches).
ParagraphListType? listTypeOfPrefix(String prefix) {
  final trimmed = prefix.trimLeft();
  if (trimmed.isEmpty) return null;
  return RegExp(r'^\d').hasMatch(trimmed) ? ParagraphListType.numbered : ParagraphListType.bullet;
}

/// Whether a matched `prefix` (as returned by [listPrefixPattern]/
/// [listPrefixLength]) is a task-list checkbox, and if so, whether it's
/// checked: `null` if `prefix` has no checkbox segment at all (a plain
/// bullet, or any numbered item — see [listPrefixPattern]'s doc comment
/// on why numbered items never have one), `true`/`false` for `'[x] '`/
/// `'[X] '` vs `'[ ] '`.
bool? checkboxStateOfPrefix(String prefix) {
  final match = RegExp(r'\[([ xX])\] $').firstMatch(prefix);
  if (match == null) return null;
  return match.group(1) != ' ';
}

/// The leading run of spaces/tabs at the very start of the paragraph
/// beginning at `paragraphStart` — nesting indentation, whether or not
/// that paragraph actually has a list prefix after it (an unindented
/// paragraph simply returns `''`). The single canonical place this is
/// computed: every caller that used to hand-roll
/// `RegExp(r'^[ \t]*').firstMatch(...)` against a slice of `text` should
/// call this instead, so indentation is derived exactly one way
/// everywhere it's checked (list-run matching, `ParagraphBlock`
/// derivation, ...) rather than several near-identical private copies
/// that can silently drift apart — see `EditingEngine._numberedToggleEdit`'s
/// former private `indentOf` for a concrete case where that drift caused
/// a real bug: it collapsed a genuine zero-width (flush-left) indent to
/// a hardcoded `'  '`, breaking numbered-run matching for the common
/// unindented-list case.
///
/// Deliberately not restricted to paragraphs that actually have a list
/// prefix — indentation is a property of the paragraph's leading
/// whitespace, independent of whether what follows happens to be a list
/// marker.
String listIndentWhitespace(String text, int paragraphStart) {
  final windowEnd = clampInt(paragraphStart + 24, paragraphStart, text.length);
  final window = text.substring(paragraphStart, windowEnd);
  return RegExp(r'^[ \t]*').firstMatch(window)!.group(0)!;
}