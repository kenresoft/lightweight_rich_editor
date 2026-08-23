/// Lightweight, dependency-free URL detection for autolinkify.
///
/// Uses `Uri.tryParse` for structural validation; this file only finds
/// the token ending at a boundary character and decides whether a
/// schemeless token is confident enough to treat as a URL.
library;

/// A URL token found immediately before a boundary character.
class DetectedUrl {
  const DetectedUrl({required this.start, required this.end, required this.href});

  /// Start offset of the token in the text (inclusive).
  final int start;

  /// End offset of the token in the text (exclusive); the boundary
  /// character itself is not included.
  final int end;

  /// Normalized, launchable URL, e.g. `www.example.com` becomes
  /// `https://www.example.com`. The visible text is left as typed.
  final String href;
}

/// Characters that end a "word" for autolink purposes — space/newline/
/// tab only, not punctuation, since trailing punctuation is ambiguous
/// (sentence-ending `.` vs. part of the URL path).
bool isAutolinkBoundary(String char) => char == ' ' || char == '\n' || char == '\t';

/// TLDs trusted for a bare domain (no scheme, no `www.`), e.g.
/// `facebook.com`. A conservative heuristic to avoid false positives
/// like `Mr.Smith` or `e.g.`, not a real TLD list.
const _commonTlds = {
  'com', 'net', 'org', 'io', 'co', 'dev', 'app', 'ai', 'edu', 'gov',
  'me', 'info', 'biz', 'us', 'uk', 'ca', 'de', 'fr', 'jp', 'cn', 'in',
};

// Trailing punctuation trimmed off a token before treating it as a URL,
// shared by detectUrlBeforeBoundary and detectAllUrls.
final RegExp _trailingPunctuation = RegExp(r'[.,!?;:]+$');

/// Looks for a URL-shaped token immediately before [boundaryIndex] in
/// [text] (`text[boundaryIndex]` itself is excluded). Returns `null` if
/// there's no token there, or it isn't confidently URL-shaped.
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
    while (start < text.length && isAutolinkBoundary(text[start])) {
      start++;
    }
    if (start >= text.length) break;

    var end = start;
    while (end < text.length && !isAutolinkBoundary(text[end])) {
      end++;
    }

    var token = text.substring(start, end);

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
/// [token] isn't confidently a URL. Shared by autolink detection and
/// the manual link-entry dialog so both resolve to the same href.
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