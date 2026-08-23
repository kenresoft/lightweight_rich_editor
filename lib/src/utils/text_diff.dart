/// The result of diffing two whole-text strings: `text[start:end]` in the
/// old string was replaced with `insertedText` to produce the new one.
class TextDiff {
  final int start;
  final int end;
  final String insertedText;

  const TextDiff({required this.start, required this.end, required this.insertedText});

  bool get isNoOp => start == end && insertedText.isEmpty;
}

/// Diffs `oldText` against `newText` using common-prefix/common-suffix
/// matching, since Flutter's `TextField` reports only the resulting
/// whole string, not "the user typed X at position Y".
///
/// The match can be ambiguous (e.g. typing "aa" into "a" could be
/// inserting before or after); `cursorHint` (selection start before the
/// edit) breaks the tie in favor of where the caret actually was.
TextDiff diffText(String oldText, String newText, {int? cursorHint}) {
  final oldLen = oldText.length;
  final newLen = newText.length;
  final minLength = oldLen < newLen ? oldLen : newLen;

  final prefixMax = _commonPrefixLength(oldText, newText, minLength);
  final suffixMax = _commonSuffixLength(oldText, newText, minLength);

  int prefixLength;
  int suffixLength;

  if (prefixMax + suffixMax > minLength) {
    // Overlapping matches: ambiguous. Use cursorHint if it falls in the
    // overlap, otherwise prefer the longest prefix match.
    final ambiguityLow = minLength - suffixMax;
    final ambiguityHigh = prefixMax;
    prefixLength = (cursorHint != null && cursorHint >= ambiguityLow && cursorHint <= ambiguityHigh)
        ? cursorHint
        : ambiguityHigh;
    suffixLength = minLength - prefixLength;
  } else {
    prefixLength = prefixMax;
    suffixLength = suffixMax;
  }

  final deleteStart = prefixLength;
  final deleteEnd = oldLen - suffixLength;
  final insertedText = newText.substring(prefixLength, newLen - suffixLength);

  return TextDiff(start: deleteStart, end: deleteEnd, insertedText: insertedText);
}

int _commonPrefixLength(String a, String b, int max) {
  var i = 0;
  while (i < max && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

int _commonSuffixLength(String a, String b, int max) {
  var i = 0;
  while (i < max && a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
    i++;
  }
  return i;
}