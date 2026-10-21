import 'dart:typed_data';

/// Used where `dart:io` does not exist (the browser): there is no socket access,
/// so a remote picture cannot be fetched here.
Future<Uint8List?> fetchRemoteImage(
  Uri uri, {
  required Duration timeout,
  required int maxBytes,
}) async =>
    null;
