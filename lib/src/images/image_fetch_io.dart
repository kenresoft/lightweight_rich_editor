import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Downloads [uri] (`http` or `https`) with the limits described on
/// `loadImageSource`. Returns `null` for local or private addresses and on any failure.
Future<Uint8List?> fetchRemoteImage(
  Uri uri, {
  required Duration timeout,
  required int maxBytes,
}) async {
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
  request.headers.set(HttpHeaders.userAgentHeader, 'ENotebook/1.0 (note app; fetching a picture the user added)');
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
