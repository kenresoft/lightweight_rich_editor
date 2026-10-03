import 'code_block.dart';

/// An image is a block of consecutive empty rows that the paper layer draws a
/// picture over (the way a code block is a run of lines drawn on a card). Every
/// row is an ordinary one-pitch line, so the ruled grid, the forced strut and
/// every offset rule stay exactly as they are, and the note's text holds no
/// placeholder characters: an image reads as blank lines in plain text.
///
/// Each row of the block is a paragraph whose block level is
/// `img:<id>:<instance>`:
///  * `id` names the picture in the host's [RichImageStore] (letters, digits,
///    `_` and `-`);
///  * `instance` tells apart two blocks that show the same picture and sit
///    next to each other (a pasted copy), so they are two images, not one tall
///    one.
///
/// The number of rows in the run is the picture's height in rows.
const String imageBlockLevel = 'img';

/// The fewest rows an image can be resized to (and a new one is given).
const int minImageRows = 3;

/// The most rows an image can be resized to.
const int maxImageRows = 16;

/// Whether a paragraph block level denotes an image row.
bool isImageLevel(String? level) => level != null && level.startsWith('$imageBlockLevel:');

/// Whether a block level is one that spans a run of paragraphs (code or image):
/// such a run is exported as one span covering every row, blank ones included.
bool isRunBlockLevel(String? level) => isCodeBlockLevel(level) || isImageLevel(level);

final RegExp _imageLevelPattern = RegExp(r'^img:([A-Za-z0-9_\-]{1,64}):([A-Za-z0-9]{1,12})$');

/// The block level for an image row.
String imageLevelFor(String id, String instance) => '$imageBlockLevel:$id:$instance';

/// The picture id of an image level, or `null`.
String? imageIdOf(String? level) => level == null ? null : _imageLevelPattern.firstMatch(level)?.group(1);

/// A fresh instance tag for a new image block (short, unique enough within a
/// note: time-derived with a counter).
String newImageInstance() {
  _instanceCounter = (_instanceCounter + 1) & 0xFFFF;
  return (DateTime.now().microsecondsSinceEpoch ^ (_instanceCounter << 20)).toRadixString(36).substring(0, 8);
}

int _instanceCounter = 0;

/// Whether [id] is acceptable inside a level string.
bool isValidImageId(String id) => RegExp(r'^[A-Za-z0-9_\-]{1,64}$').hasMatch(id);

/// How many rows a picture of [width] x [height] gets when first inserted: its
/// height at a typical phone content width (300 logical pixels), in rows of
/// about 30, kept between [minImageRows] and 12.
int rowsForImage(num width, num height) {
  if (width <= 0 || height <= 0) return 8;
  final rows = ((300 * height / width) / 30).round();
  return rows < minImageRows ? minImageRows : (rows > 12 ? 12 : rows);
}

/// A block of image rows in a document: its extent and identity.
class ImageRun {
  const ImageRun({required this.start, required this.end, required this.rows, required this.level, required this.id});

  /// Offset of the first row / end of the last row.
  final int start;
  final int end;
  final int rows;

  /// The block level shared by its rows (`img:<id>:<instance>`).
  final String level;

  /// The picture's id in the host's store.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ImageRun && other.start == start && other.end == end && other.rows == rows && other.level == level;

  @override
  int get hashCode => Object.hash(start, end, rows, level);

  @override
  String toString() => 'ImageRun($start..$end, $rows rows, $level)';
}

/// The id a picture block carries while its bytes are still being fetched (an
/// imported `<img>` / `![](url)`); it is replaced by the stored picture's id.
const String pendingImageId = 'pending';

/// A picture found by an importer: where it came from, and the block level of
/// the placeholder rows written for it in the imported text.
class ImportedImage {
  const ImportedImage({required this.level, required this.source, this.alt = ''});

  /// The placeholder block's level (`img:pending:<instance>`).
  final String level;

  /// An `http(s)` address or a `data:image/...` URI.
  final String source;

  /// The alternative text, if the source gave one.
  final String alt;
}

/// The most pictures one paste or import brings in; a whole web page can have
/// hundreds. (They are fetched a few at a time, and one address is fetched once.)
const int maxImportedImages = 200;

/// The most picture data one paste brings in; past it the rest of the page's pictures
/// are left out (a page of big photos would otherwise fill the phone and every backup).
const int maxImportedImageBytes = 30 * 1024 * 1024;

/// What became of the pictures of a paste or import.
class ImageImportReport {
  const ImageImportReport({required this.added, required this.failed, required this.limited, this.limit = maxImportedImages, this.skipped = 0});

  /// Pictures left out because the paste had already brought in [maxImportedImageBytes].
  final int skipped;

  /// The most pictures one paste could bring in.
  final int limit;

  /// Pictures now in the note.
  final int added;

  /// Pictures that could not be had (offline, gone, too big, not a picture).
  final int failed;

  /// Whether the page had more pictures than [maxImportedImages] (the rest were left out).
  final bool limited;
}

/// Whether [source] is something an importer may fetch: a web address or an
/// inline `data:image/...` URI.
bool isImportableImageSource(String source) {
  final s = source.trimLeft().toLowerCase();
  return s.startsWith('https://') || s.startsWith('http://') || s.startsWith('data:image/');
}

/// The picture address of an `<img>` as pages really write it: lazy-loading pages keep
/// the real address in `data-src` (and a tiny `data:` placeholder in `src`), responsive
/// ones in `srcset` / a `<picture>`'s `<source>` (the widest candidate is taken), and
/// some start with `//` (https). Returns `null` when there is nothing to fetch.
String? pickImageSource({
  String src = '',
  String dataSrc = '',
  String srcset = '',
  String sourceSrcset = '',
}) {
  String fix(String s) {
    final t = s.trim();
    return t.startsWith('//') ? 'https:$t' : t;
  }

  String widest(String set) => bestSrcsetCandidate(set);

  final candidates = <String>[
    fix(src),
    fix(dataSrc),
    fix(widest(srcset)),
    fix(widest(sourceSrcset)),
  ].where(isImportableImageSource).toList();
  if (candidates.isEmpty) return null;
  // A short `data:` address is a placeholder (a 1x1 gif); a real address beats it.
  for (final c in candidates) {
    if (!(c.toLowerCase().startsWith('data:') && c.length < 400)) return c;
  }
  return candidates.first;
}

/// The address to take from a `srcset`. Candidates are separated by a comma *followed by
/// whitespace*; a comma inside an address (`.../fill,aspectratio:3x4,width:375`, as image
/// services write them) belongs to the address. Of the candidates the one just big enough
/// for a phone-width picture is taken (about 800 px: `2x`, or `800w` and up), else the
/// biggest there is, so a page's 4000 px original is not downloaded for a note.
String bestSrcsetCandidate(String set) {
  final tokens = set.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final found = <({String url, double px})>[];
  var i = 0;
  while (i < tokens.length) {
    var url = tokens[i++];
    var descriptor = '';
    if (url.endsWith(',')) {
      url = url.replaceFirst(RegExp(r',+$'), '');
    } else if (i < tokens.length && !tokens[i].contains('/') && !tokens[i].startsWith('http')) {
      descriptor = tokens[i++];
      descriptor = descriptor.replaceFirst(RegExp(r',+$'), '');
    }
    if (url.isEmpty) continue;
    final n = double.tryParse(descriptor.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final px = descriptor.endsWith('w') ? n : (descriptor.endsWith('x') ? n * 400 : 0.0);
    found.add((url: url, px: px));
  }
  if (found.isEmpty) return '';
  final enough = found.where((c) => c.px >= 800).toList()..sort((a, b) => a.px.compareTo(b.px));
  if (enough.isNotEmpty) return enough.first.url;
  found.sort((a, b) => b.px.compareTo(a.px));
  return found.first.url;
}
