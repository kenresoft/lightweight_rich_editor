import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'image_fetch_stub.dart' if (dart.library.io) 'image_fetch_io.dart';

/// Fetches the bytes of a picture named by a web address or an inline
/// `data:image/...` URI. Returns `null` when it cannot be had: unreachable, too
/// slow, too big, not a picture (this does not decode; callers do), or an
/// address that is not `http(s)`.
///
/// Bounded on purpose: a [timeout] for the whole fetch, at most [maxBytes] read
/// (a response announcing more, or streaming more, is dropped), and at most a few
/// redirects. Nothing is cached here; the caller stores what it keeps.
///
/// Inline `data:` URIs work on every platform. Web addresses are fetched where
/// `dart:io` is available (not in a browser, where this returns `null`).
Future<Uint8List?> loadImageSource(
  String source, {
  Duration timeout = const Duration(seconds: 12),
  int maxBytes = 15 * 1024 * 1024,
}) async {
  final s = source.trim();
  if (s.toLowerCase().startsWith('data:')) return _decodeDataUri(s, maxBytes);
  final uri = Uri.tryParse(s);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return null;
  return fetchRemoteImage(uri, timeout: timeout, maxBytes: maxBytes);
}

Uint8List? _decodeDataUri(String uri, int maxBytes) {
  final comma = uri.indexOf(',');
  if (comma < 0) return null;
  final header = uri.substring(5, comma).toLowerCase();
  final payload = uri.substring(comma + 1);
  try {
    final bytes = header.contains(';base64')
        ? base64.decode(base64.normalize(Uri.decodeComponent(payload).replaceAll(RegExp(r'\s'), '')))
        : Uint8List.fromList(Uri.decodeComponent(payload).codeUnits);
    return bytes.isEmpty || bytes.length > maxBytes ? null : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
}
