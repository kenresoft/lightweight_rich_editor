import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../clipboard/native/rich_clipboard_platform.dart';
import '../commands/composite_command.dart';
import '../commands/editor_command.dart';
import '../commands/replace_range_command.dart';
import '../commands/set_header_level_command.dart';
import '../core/editor_selection.dart';
import '../images/image_prepare.dart';
import '../images/image_source.dart';
import '../images/rich_image_store.dart';
import '../models/image_block.dart';
import 'rich_editor_controller.dart';

/// Putting pictures into a document, and resizing them. A picture is a block of
/// blank rows (see `image_block.dart`), so all of this is ordinary paragraph and
/// text edits, and each action is a single undo step.
extension RichEditorImages on RichEditorController {
  /// Reads the picture [bytes], stores it, and inserts it as a block at the caret
  /// (on its own rows: a line in progress is split around it). Returns `false`
  /// if there is no [imageStore], or the bytes are not a picture.
  Future<bool> insertImageBytes(Uint8List bytes) async {
    final store = imageStore;
    if (store == null) return false;
    final prepared = await prepareImage(bytes);
    if (prepared == null) return false;
    final String id;
    try {
      id = await store.save(prepared.bytes);
    } catch (_) {
      return false;
    }
    if (!isValidImageId(id)) return false;
    insertImageBlock(id, rows: rowsForImage(prepared.width, prepared.height));
    return true;
  }

  /// Fetches the picture at [source] (a web address or a `data:image/...` URI),
  /// stores it and inserts it at the caret. Returns `false` if there is no
  /// [imageStore], or the address cannot be fetched or is not a picture. The
  /// picture is kept in the store, so the note shows it offline afterwards.
  ///
  /// The picture's place appears at once as a quiet card, filled in when the bytes
  /// arrive (so a slow address is visibly "on its way"), and removed again if the
  /// address fails.
  Future<bool> insertImageFromSource(String source) async {
    if (imageStore == null) return false;
    final level = insertImageBlock(pendingImageId, rows: 6);
    if (level == null) return false;
    return _resolveImported(ImportedImage(level: level, source: source));
  }

  /// Fills in the placeholder blocks an import left for pictures ([items], from a
  /// paste or `pasteHtml`/`pasteMarkdown`): each is fetched, stored and shown in
  /// place, as one undo step per picture. A picture that cannot be had removes
  /// its placeholder, so a failed fetch leaves no empty block behind. Fetches run
  /// side by side and never block typing.
  Future<void> resolveImportedImages(List<ImportedImage> items) async {
    if (items.isEmpty) return;
    await Future.wait([for (final item in items) _resolveImported(item)]);
  }

  // Fetches and shows one placeholder's picture; `false` when it could not be
  // had (the placeholder is then removed).
  Future<bool> _resolveImported(ImportedImage item) async {
    final store = imageStore;
    String? id;
    PreparedImage? prepared;
    if (store != null) {
      final bytes = await loadImageSource(item.source);
      if (bytes != null) prepared = await prepareImage(bytes);
      if (prepared != null) {
        try {
          id = await store.save(prepared.bytes);
          await _rememberAddress(store, id, item.source);
        } catch (_) {
          id = null;
        }
      }
    }
    if (disposed) return false;
    final run = imageRunByLevel(item.level);
    if (run == null) return id != null; // deleted in the meantime
    if (id == null || prepared == null || !isValidImageId(id)) {
      discardImage(run);
      return false;
    }
    _swapPicture(run, id, prepared);
    return true;
  }

  // Keeps the web address a picture came from (not a `data:` URI, which is the
  // picture itself) so a later "replace" can offer it for correction. A host that
  // cannot keep it must not make the picture fail, so errors here are ignored.
  Future<void> _rememberAddress(RichImageStore store, String id, String source) async {
    final s = source.trim();
    if (!s.toLowerCase().startsWith('http')) return;
    try {
      await store.rememberSource(id, s);
    } catch (_) {
      // best effort
    }
  }

  // Shows the stored picture [id] in the block [run] (same place, same instance
  // tag), with as many rows as the new picture's shape asks for, as one undo
  // step. The caret keeps its place in the text around the block.
  void _swapPicture(ImageRun run, String id, PreparedImage prepared) {
    final target = rowsForImage(prepared.width, prepared.height);
    final instance = run.level.substring(run.level.lastIndexOf(':') + 1);
    final level = imageLevelFor(id, instance);
    final delta = target - run.rows;
    final cmds = <EditorCommand>[
      if (delta > 0) ReplaceRangeCommand(start: run.end, end: run.end, text: '\n' * delta, attributesForInsertion: const {}),
      if (delta < 0) ReplaceRangeCommand(start: run.end + delta, end: run.end, text: ''),
      for (var i = 0; i < target; i++) SetHeaderLevelCommand(EditorSelection.collapsed(run.start + i), level),
    ];
    final old = selection;
    commands.dispatch(CompositeCommand(cmds));
    if (old.isValid) {
      int map(int o) => o >= run.end ? o + delta : (o > run.start + target ? run.start + target : o);
      selection = TextSelection(baseOffset: map(old.baseOffset), extentOffset: map(old.extentOffset));
    }
  }

  /// Replaces the picture of the block [run] with [bytes]: same place in the note,
  /// one undo step. Returns `false` (and changes nothing) if there is no
  /// [imageStore], [bytes] is not a picture, or the block is gone.
  Future<bool> replaceImageBytes(ImageRun run, Uint8List bytes, {String? source}) async {
    final store = imageStore;
    if (store == null) return false;
    final prepared = await prepareImage(bytes);
    if (prepared == null) return false;
    final String id;
    try {
      id = await store.save(prepared.bytes);
    } catch (_) {
      return false;
    }
    if (source != null) await _rememberAddress(store, id, source);
    if (disposed || !isValidImageId(id)) return false;
    final current = imageRunByLevel(run.level); // it may have moved while the bytes were read
    if (current == null) return false;
    _swapPicture(current, id, prepared);
    return true;
  }

  /// Like [replaceImageBytes], with the new picture fetched from a web address or
  /// a `data:image/...` URI.
  Future<bool> replaceImageFromSource(ImageRun run, String source) async {
    if (imageStore == null) return false;
    final bytes = await loadImageSource(source);
    if (bytes == null || disposed) return false;
    return replaceImageBytes(run, bytes, source: source);
  }

  /// Inserts the picture [id] (already in the store) as a block of [rows] rows at
  /// the caret, with the caret left on the line after it. Returns the block's
  /// level (`img:<id>:<instance>`), or `null` if nothing was inserted.
  String? insertImageBlock(String id, {required int rows}) {
    if (!isValidImageId(id)) return null;
    final n = rows.clamp(minImageRows, maxImageRows);
    var sel = selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: document.length);
    final within = imageRunAt(sel.start);
    var start = sel.start;
    var end = sel.end;
    if (within != null) start = end = within.end; // below the picture the caret is on

    final para = document.paragraphs.paragraphAt(start)!;
    final textBefore = document.text.substring(para.start, start);
    // A line in progress keeps the part before the caret above the picture; a
    // caret on an empty line uses that line as the picture's first row.
    final needBefore = textBefore.isNotEmpty || within != null;
    final inserted = '${needBefore ? '\n' : ''}${'\n' * (n - 1)}\n';
    final firstRow = start + (needBefore ? 1 : 0);
    final level = imageLevelFor(id, newImageInstance());

    commands.dispatch(CompositeCommand([
      ReplaceRangeCommand(start: start, end: end, text: inserted, attributesForInsertion: const {}),
      // One command per row: an empty row is a zero-width range, which a
      // multi-row selection would skip at its end.
      for (var i = 0; i < n; i++) SetHeaderLevelCommand(EditorSelection.collapsed(firstRow + i), level),
    ]));
    selection = TextSelection.collapsed(offset: firstRow + n);
    return level;
  }

  /// Makes the picture [delta] rows taller (or shorter), within
  /// [minImageRows]..[maxImageRows]. The caret stays on the picture.
  ///
  /// With [moveCaret] off (a resize the user did not ask for with the picture
  /// selected, such as following a change of the text width) the caret stays on
  /// the text it was on.
  void resizeImage(ImageRun run, int delta, {bool moveCaret = true}) {
    final target = (run.rows + delta).clamp(minImageRows, maxImageRows);
    if (target == run.rows) return;
    final old = selection;
    if (target > run.rows) {
      final add = target - run.rows;
      final t = run.end;
      final cmds = <EditorCommand>[
        ReplaceRangeCommand(start: t, end: t, text: '\n' * add, attributesForInsertion: const {}),
        for (var i = 1; i <= add; i++) SetHeaderLevelCommand(EditorSelection.collapsed(t + i), run.level),
      ];
      commands.dispatch(CompositeCommand(cmds));
    } else {
      final remove = run.rows - target;
      // The last rows go: the line breaks just before the last row's start.
      commands.dispatch(ReplaceRangeCommand(start: run.end - remove, end: run.end, text: ''));
    }
    if (moveCaret || !old.isValid) {
      selection = TextSelection.collapsed(offset: run.start);
    } else {
      final change = target - run.rows;
      int map(int o) => o >= run.end ? o + change : (o > run.end + change ? run.end + change : o);
      selection = TextSelection(baseOffset: map(old.baseOffset), extentOffset: map(old.extentOffset));
    }
  }

  /// If the system clipboard holds a picture, inserts it and returns `true`;
  /// otherwise `false`.
  ///
  /// A plain paste prefers text when the clipboard has some, except when that
  /// text is just a web address (a browser's "Copy image" puts the picture's own
  /// URL next to it): then the picture is what was copied. Pass [force] (an
  /// explicit "Paste image") to insert the picture whatever else is there.
  Future<bool> pasteImageFromClipboard({bool force = false}) async {
    if (imageStore == null) return false;
    final image = await RichClipboardPlatform.getImage();
    if (image == null) return false;
    if (!force) {
      final data = await RichClipboardPlatform.getData();
      final text = data.text?.trim() ?? '';
      final loneAddress = RegExp(r'^(https?://|content://|file://)\S+$').hasMatch(text);
      if (text.isNotEmpty && !loneAddress) return false;
    }
    return insertImageBytes(image);
  }
}
