import 'clamp_int.dart';

/// Matches a literal list-style prefix anchored at the start of the
/// string it's tested against: optional leading indentation, then
/// `'- '`/`'* '`/`'+ '` (bullets, optionally followed by a GFM checkbox
/// segment `'[ ] '`/`'[x] '`) or a `'N. '` number (never a checkbox).
/// List formatting is plain text, not a stored attribute; always used
/// via [RegExp.matchAsPrefix] against a pre-sliced substring.
final RegExp listPrefixPattern = RegExp(r'^[ \t]*(?:[-*+] (?:\[[ xX]\] )?|\d{1,9}\. )');

/// Length of the list-style prefix (if any, indentation included)
/// starting at `paragraphStart` in `text`, or 0 if the paragraph doesn't
/// start with one. O(1): only scans a small fixed window.
int listPrefixLength(String text, int paragraphStart) {
  final windowEnd = clampInt(paragraphStart + 24, paragraphStart, text.length);
  final window = text.substring(paragraphStart, windowEnd);
  final match = listPrefixPattern.matchAsPrefix(window);
  return match?.end ?? 0;
}

/// The literal prefix that continues this list on the next line after
/// Enter: unchanged for a bullet, incremented for a numbered marker
/// (`'3. '` -> `'4. '`), and a checkbox segment resets to unchecked.
String nextListPrefix(String prefix) {
  final numbered = RegExp(r'^([ \t]*)(\d+)(\. )$').firstMatch(prefix);
  if (numbered != null) {
    final leading = numbered.group(1)!;
    final n = int.parse(numbered.group(2)!);
    return '$leading${n + 1}${numbered.group(3)}';
  }
  return prefix.replaceFirst(RegExp(r'\[[xX]\] $'), '[ ] ');
}

/// Which kind of list a matched prefix represents.
enum ParagraphListType { bullet, numbered }

/// The [ParagraphListType] a matched `prefix` represents, or `null` if
/// `prefix` doesn't match [listPrefixPattern].
ParagraphListType? listTypeOfPrefix(String prefix) {
  final trimmed = prefix.trimLeft();
  if (trimmed.isEmpty) return null;
  return RegExp(r'^\d').hasMatch(trimmed) ? ParagraphListType.numbered : ParagraphListType.bullet;
}

/// Whether a matched `prefix` has a task-list checkbox, and if so,
/// whether it's checked: `null` if there's no checkbox segment.
bool? checkboxStateOfPrefix(String prefix) {
  final match = RegExp(r'\[([ xX])\] $').firstMatch(prefix);
  if (match == null) return null;
  return match.group(1) != ' ';
}

/// The leading run of spaces/tabs at the start of the paragraph
/// beginning at `paragraphStart` (`''` if unindented), regardless of
/// whether a list prefix follows. The single canonical place indentation
/// is computed — call this rather than re-deriving it, so it stays
/// consistent everywhere it's checked.
String listIndentWhitespace(String text, int paragraphStart) {
  final windowEnd = clampInt(paragraphStart + 24, paragraphStart, text.length);
  final window = text.substring(paragraphStart, windowEnd);
  return RegExp(r'^[ \t]*').firstMatch(window)!.group(0)!;
}