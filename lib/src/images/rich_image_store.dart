import 'dart:typed_data';

/// Where the pictures of a document live. The document itself only holds a short
/// id per picture (in the block level of its rows), so a note stays small and
/// loading it never touches picture bytes; the host decides where bytes go (a
/// file per picture, a database, the cloud).
abstract class RichImageStore {
  /// Stores [bytes] (an encoded PNG/JPEG/WebP/GIF) and returns the id the
  /// document will refer to it by. The id must be letters, digits, `_` or `-`
  /// and at most 64 characters.
  Future<String> save(Uint8List bytes);

  /// The stored bytes for [id], or `null` if they are gone.
  Future<Uint8List?> load(String id);

  /// Forgets [id]. Optional: a host may keep pictures a note once used, so that
  /// undo can bring a deleted picture back.
  Future<void> delete(String id) async {}
}
