import 'clamp_int.dart';

/// Matches a literal list-style prefix anchored at the start of the
/// string it's tested against: optional leading indentation, then
/// `'- '`/`'* '`/`'+ '` (bullets, optionally followed by a GFM checkbox
/// segment `'[ ] '`/`'[x] '`) or a `'N. '` number (never a checkbox).
/// List formatting is plain text, not a stored attribute; always used
/// via [RegExp.matchAsPrefix] against a pre-sliced substring.
final RegExp listPrefixPattern = RegExp(r'^[ \t]*(?:[-*+] (?:\[[ xX]\] )?|\d{1,9}\. )');

/// The marker alone: `'- '`, `'- [ ] '`, `'12. '`. The longest is a number of nine digits and `'. '`.
final RegExp _markerPattern = RegExp(r'^(?:[-*+] (?:\[[ xX]\] )?|\d{1,9}\. )');
const int _longestMarker = 12;

/// Where the run of spaces and tabs that starts the paragraph at [paragraphStart] ends. However
/// deep the indentation is, the marker after it is found: a fixed window over the whole prefix
/// lost the marker (or its checkbox) once a line was indented about twenty spaces.
int _indentEnd(String text, int paragraphStart) {
  var i = paragraphStart;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) break;
    i++;
  }
  return i;
}

/// Length of the list-style prefix (if any, indentation included)
/// starting at `paragraphStart` in `text`, or 0 if the paragraph doesn't
/// start with one. Scans the indentation, then only a small window for the marker.
int listPrefixLength(String text, int paragraphStart) {
  final markerStart = _indentEnd(text, paragraphStart);
  final windowEnd = clampInt(markerStart + _longestMarker, markerStart, text.length);
  final match = _markerPattern.matchAsPrefix(text.substring(markerStart, windowEnd));
  return match == null ? 0 : (markerStart - paragraphStart) + match.end;
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
String listIndentWhitespace(String text, int paragraphStart) =>
    text.substring(paragraphStart, _indentEnd(text, paragraphStart));
/// The deepest indentation a list item can be given: six levels of two spaces. Deeper than that
/// pushes the text off a phone's screen, and a line that deep is hard to tell from a mistake.
const int maxListIndent = 12;

/// [prefix] with its indentation one level (two spaces) less, or null when the item is at the top
/// level already (two spaces or fewer: a new bullet starts with two, so that is the first level).
/// Used by Enter on an empty item and Backspace at the start of one, which step out before they
/// take the item out of the list.
String? outdentedPrefix(String prefix) {
  final indent = RegExp(r'^[ \t]*').stringMatch(prefix) ?? '';
  if (indent.length <= 2) return null;
  return '${indent.substring(2)}${prefix.substring(indent.length)}';
}
