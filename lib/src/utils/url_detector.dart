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

// A telephone number, conservatively: international (`+` and 8-15 digits), a
// national number with a leading 0 (10-11 digits), or the 3-3-4 pattern with
// separators. A bare run of digits (an id, a year, an amount) is not a phone.
String? _phoneHref(String token) {
  final digits = token.replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^\+\d[\d\-.()]{6,18}\d$').hasMatch(token) && digits.length >= 8 && digits.length <= 15) {
    return 'tel:+$digits';
  }
  if (RegExp(r'^0\d{9,10}$').hasMatch(token)) return 'tel:$token';
  if (RegExp(r'^\(?\d{3}\)?[-.]\d{3}[-.]\d{4}$').hasMatch(token)) return 'tel:$digits';
  return null;
}

final RegExp _emailToken = RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$');

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
  // An address is a mail link, never `https://name@host` (which would parse as
  // the host with a user name and open a web page).
  if (_emailToken.hasMatch(token)) return 'mailto:$token';
  if (token.startsWith('mailto:') && _emailToken.hasMatch(token.substring(7))) return token;
  final phone = _phoneHref(token);
  if (phone != null) return phone;

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