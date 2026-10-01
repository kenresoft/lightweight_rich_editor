import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Fetches the bytes of a picture named by a web address or an inline
/// `data:image/...` URI. Returns `null` when it cannot be had: unreachable, too
/// slow, too big, not a picture (this does not decode; callers do), or an
/// address that is not `http(s)`.
///
/// Bounded on purpose: a [timeout] for the whole fetch, at most [maxBytes] read
/// (a response announcing more, or streaming more, is dropped), and at most a few
/// redirects. Nothing is cached here; the caller stores what it keeps.
Future<Uint8List?> loadImageSource(
  String source, {
  Duration timeout = const Duration(seconds: 12),
  int maxBytes = 15 * 1024 * 1024,
}) async {
  final s = source.trim();
  if (s.toLowerCase().startsWith('data:')) return _decodeDataUri(s, maxBytes);
  var uri = Uri.tryParse(s);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return null;
  // Pasted pages must not make the app probe the user's own network.
  if (_isLocalHost(uri.host)) return null;
  if (uri.scheme == 'http') uri = uri.replace(scheme: 'https'); // cleartext is blocked on modern systems anyway

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..autoUncompress = true;
  try {
    return await _fetch(client, uri, maxBytes).timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List?> _fetch(HttpClient client, Uri uri, int maxBytes) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.5');
  request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (compatible; NotebookImageFetch)');
  request.followRedirects = true;
  request.maxRedirects = 5;
  final response = await request.close();
  if (response.statusCode != 200) {
    await response.drain<void>();
    return null;
  }
  final announced = response.contentLength;
  if (announced > maxBytes) {
    await response.drain<void>();
    return null;
  }
  final out = BytesBuilder(copy: false);
  await for (final chunk in response) {
    out.add(chunk);
    if (out.length > maxBytes) return null;
  }
  return out.isEmpty ? null : out.takeBytes();
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
bool _isLocalHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal')) return true;
  final ip = InternetAddress.tryParse(h);
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 10 || b[0] == 0 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
  }
  return (b[0] & 0xFE) == 0xFC; // unique-local fc00::/7
}
