import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A picture ready to be stored: its encoded bytes and pixel size.
class PreparedImage {
  const PreparedImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Reads the size of an encoded picture without decoding it, and shrinks one that
/// is too big to be worth keeping: bytes over [maxBytes] or a side over
/// [maxSide] are re-encoded (PNG) with the longest side at [maxSide]. Returns
/// `null` if [bytes] is not a picture the engine can read.
///
/// Everything heavy runs on the engine's own threads; the caller only awaits.
Future<PreparedImage?> prepareImage(
  Uint8List bytes, {
  int maxBytes = 6 * 1024 * 1024,
  int maxSide = 2048,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    if (w <= 0 || h <= 0) return null;
    final longest = math.max(w, h);
    if (bytes.length <= maxBytes && longest <= 4096) return PreparedImage(bytes, w, h);

    final scale = longest > maxSide ? maxSide / longest : 1.0;
    final tw = math.max(1, (w * scale).round());
    final th = math.max(1, (h * scale).round());
    codec = await descriptor.instantiateCodec(targetWidth: tw, targetHeight: th);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) return null;
    return PreparedImage(data.buffer.asUint8List(), tw, th);
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
