import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'rich_image_store.dart';

/// Decoded pictures for the paper layer: a small, bounded, least-recently-used
/// cache that never decodes at full size and never blocks a frame.
///
/// * Bytes come from the [RichImageStore] asynchronously; decoding runs on the
///   engine's image thread, at most as wide as the picture is drawn (times the
///   device pixel ratio), so a 12-megapixel photo costs a few megabytes, not 48.
/// * Only pictures that are (nearly) on screen are asked for (see [ensure]).
/// * The total of decoded pixels is capped at [maxBytes]; the least recently
///   painted pictures are released first.
/// * Painting only ever calls [peek], which is a map lookup.
///
/// Listeners (the paper layer) are told when a picture finishes decoding.
class RichImageCache extends ChangeNotifier {
  RichImageCache(this.store, {this.maxBytes = 48 * 1024 * 1024});

  final RichImageStore store;

  /// Upper bound of decoded pixel memory, in bytes.
  final int maxBytes;

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  final Set<String> _loading = {};
  final Set<String> _failed = {};
  int _bytes = 0;
  bool _disposed = false;

  /// The decoded picture for [id] if it is in memory, marking it recently used.
  ui.Image? peek(String id) {
    final entry = _entries.remove(id);
    if (entry == null) return null;
    _entries[id] = entry;
    return entry.image;
  }

  /// Whether loading [id] was tried and failed (bytes gone, not an image).
  bool hasFailed(String id) => _failed.contains(id);

  /// Whether [id] is in memory or being loaded.
  bool isLoadedOrLoading(String id) => _entries.containsKey(id) || _loading.contains(id);

  /// Makes sure [id] is (being) decoded at about [targetWidth] physical pixels.
  /// Cheap when it already is: a lookup.
  void ensure(String id, int targetWidth) {
    if (_disposed || _failed.contains(id) || _loading.contains(id)) return;
    final entry = _entries[id];
    // Enough already (within a quarter), or the picture is smaller than asked.
    if (entry != null && (entry.width >= targetWidth * 0.75 || entry.nativeSize)) return;
    _loading.add(id);
    _load(id, targetWidth < 16 ? 16 : (targetWidth > 2048 ? 2048 : targetWidth));
  }

  /// Drops [id] (its picture was replaced or removed) so the next [ensure]
  /// loads it afresh.
  void evict(String id) {
    final entry = _entries.remove(id);
    if (entry != null) {
      _bytes -= entry.bytes;
      entry.image.dispose();
    }
    _failed.remove(id);
  }

  Future<void> _load(String id, int targetWidth) async {
    ui.Codec? codec;
    try {
      final bytes = await store.load(id);
      if (_disposed) return;
      if (bytes == null || bytes.isEmpty) {
        _failed.add(id);
        return;
      }
      codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth, allowUpscaling: false);
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      final image = frame.image;
      final previous = _entries.remove(id);
      if (previous != null) {
        _bytes -= previous.bytes;
        previous.image.dispose();
      }
      final entry = _Entry(image, image.width * image.height * 4, targetWidth);
      _entries[id] = entry;
      _bytes += entry.bytes;
      _trim(keep: id);
      notifyListeners();
    } catch (_) {
      _failed.add(id);
      if (!_disposed) notifyListeners();
    } finally {
      codec?.dispose();
      _loading.remove(id);
    }
  }

  void _trim({required String keep}) {
    while (_bytes > maxBytes && _entries.length > 1) {
      final oldest = _entries.keys.first;
      if (oldest == keep) break;
      final entry = _entries.remove(oldest)!;
      _bytes -= entry.bytes;
      entry.image.dispose();
    }
  }

  @visibleForTesting
  int get cachedCount => _entries.length;

  @visibleForTesting
  int get cachedBytes => _bytes;

  @override
  void dispose() {
    _disposed = true;
    for (final e in _entries.values) {
      e.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
    super.dispose();
  }
}

class _Entry {
  _Entry(this.image, this.bytes, this.requestedWidth);

  final ui.Image image;
  final int bytes;
  final int requestedWidth;

  int get width => image.width;

  /// The picture decoded smaller than asked: it is its own native size, so a
  /// larger request would not give more.
  bool get nativeSize => image.width < requestedWidth;
}
