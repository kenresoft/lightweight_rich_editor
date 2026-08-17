/// Lightweight, dependency-free URL detection for autolinkify.
///
/// Deliberately avoids a "one true URL regex" or a URL-parsing
/// package — `Uri.tryParse` (`dart:core`) does the structural
/// validation; this file is only responsible for (a) finding the
/// token ending at a boundary character and (b) deciding whether a
/// *schemeless* token is confident enough to treat as a URL.
library;

/// A URL token found immediately before a boundary character.
class DetectedUrl {
  const DetectedUrl({required this.start, required this.end, required this.href});

  /// Start offset of the token in the text (inclusive).
  final int start;

  /// End offset of the token in the text (exclusive) — the boundary
  /// character itself is NOT included in the range.
  final int end;

  /// Normalized, launchable URL — e.g. `www.example.com` becomes
  /// `https://www.example.com`. This is what gets stored as the link
  /// attribute's value; the visible text is left exactly as typed.
  final String href;
}

/// Characters that end a "word" for autolink purposes. Deliberately
/// narrow — space/newline/tab only, not punctuation like `)` or `,` —
/// since trailing punctuation is ambiguous (is a `.` the end of a URL
/// path or the end of the sentence?) and getting it wrong silently
/// over- or under-linkifies either way.
bool isAutolinkBoundary(String char) => char == ' ' || char == '\n' || char == '\t';

/// TLDs trusted for a *bare* domain (no scheme, no `www.`), e.g.
/// `facebook.com`. Deliberately conservative — this is a heuristic to
/// avoid false positives like `Mr.Smith` or `e.g.`, not a real TLD
/// list. Schemed and `www.`-prefixed tokens don't consult this at all;
/// the scheme/prefix is already a strong enough signal by itself.
const _commonTlds = {
  'com', 'net', 'org', 'io', 'co', 'dev', 'app', 'ai', 'edu', 'gov',
  'me', 'info', 'biz', 'us', 'uk', 'ca', 'de', 'fr', 'jp', 'cn', 'in',
};

/// Trailing characters trimmed off a token before treating it as a URL
/// — shared by [detectUrlBeforeBoundary] and [detectAllUrls] so a
/// sentence-ending `.`/`,`/etc. right after a URL never becomes part of
/// the link either way a URL gets detected, live-typed or pasted.
/// Deliberately not treated as an [isAutolinkBoundary] character itself
/// (see that function's doc comment on why boundary detection stays
/// narrow) — trimming happens *after* the token is already found, so a
/// URL is still only ever considered "finished" once a real boundary
/// char follows it, just without dragging trailing punctuation along
/// for the ride once it has.
final RegExp _trailingPunctuation = RegExp(r'[.,!?;:]+$');

/// Looks for a URL-shaped token immediately before [boundaryIndex] in
/// [text] — `text[boundaryIndex]` is the boundary char itself (e.g.
/// the space just typed) and is excluded from the token. Returns
/// `null` if there's no token there, or it isn't confidently
/// URL-shaped.
///
/// Only inspects the single token ending at [boundaryIndex] — it does
/// not scan the document. The caller is expected to invoke this only
/// when the just-inserted character is itself a boundary char, which
/// is what keeps a URL from being linkified while it's still being
/// typed.
DetectedUrl? detectUrlBeforeBoundary(String text, int boundaryIndex) {
  if (boundaryIndex <= 0 || boundaryIndex > text.length) return null;

  var start = boundaryIndex;
  while (start > 0 && !isAutolinkBoundary(text[start - 1])) {
    start--;
  }
  var end = boundaryIndex;
  var token = text.substring(start, end);
  if (token.isEmpty) return null;

  final trimMatch = _trailingPunctuation.firstMatch(token);
  if (trimMatch != null) {
    end -= trimMatch.group(0)!.length;
    token = text.substring(start, end);
    if (token.isEmpty) return null;
  }

  final href = normalizeUrlToken(token);
  if (href == null) return null;

  return DetectedUrl(start: start, end: end, href: href);
}

/// Finds all URL-shaped tokens in [text] and returns them as [DetectedUrl]s.
List<DetectedUrl> detectAllUrls(String text) {
  final results = <DetectedUrl>[];
  var start = 0;
  while (start < text.length) {
    // Skip boundaries
    while (start < text.length && isAutolinkBoundary(text[start])) {
      start++;
    }
    if (start >= text.length) break;

    // Find end of token
    var end = start;
    while (end < text.length && !isAutolinkBoundary(text[end])) {
      end++;
    }

    var token = text.substring(start, end);

    // Trim trailing punctuation that isn't part of a URL -- same rule
    // (and same shared pattern) detectUrlBeforeBoundary applies.
    var trimmedEnd = end;
    final trimMatch = _trailingPunctuation.firstMatch(token);
    if (trimMatch != null) {
      trimmedEnd -= trimMatch.group(0)!.length;
      token = text.substring(start, trimmedEnd);
    }

    final href = normalizeUrlToken(token);
    if (href != null) {
      results.add(DetectedUrl(start: start, end: trimmedEnd, href: href));
    }
    start = end;
  }
  return results;
}

/// Returns the normalized/launchable href for [token], or `null` if
/// [token] isn't confidently a URL. Exposed separately (not just
/// inlined into [detectUrlBeforeBoundary]) so the manual link-entry
/// dialog can reuse the exact same normalization rule — "example.com"
/// typed into the dialog and "example.com " autolinked in the body
/// text should both resolve to the same href.
String? normalizeUrlToken(String token) {
  if (token.startsWith('http://') || token.startsWith('https://')) {
    final uri = Uri.tryParse(token);
    if (uri == null || uri.host.isEmpty) return null;
    return token;
  }

  if (token.startsWith('www.')) {
    final uri = Uri.tryParse('https://$token');
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) return null;
    return 'https://$token';
  }

  // Bare domain — the ambiguous case. Require a dot-separated
  // structure ending in a known TLD before trusting it.
  final dotIndex = token.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == token.length - 1) return null;
  final tld = token.substring(dotIndex + 1).toLowerCase();
  if (!_commonTlds.contains(tld)) return null;

  final uri = Uri.tryParse('https://$token');
  if (uri == null || uri.host.isEmpty) return null;
  return 'https://$token';
}