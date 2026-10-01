import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../clipboard/native/rich_clipboard_platform.dart';
import '../commands/composite_command.dart';
import '../commands/editor_command.dart';
import '../commands/replace_range_command.dart';
import '../commands/set_header_level_command.dart';
import '../core/editor_selection.dart';
import '../images/image_prepare.dart';
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

  /// Inserts the picture [id] (already in the store) as a block of [rows] rows at
  /// the caret, with the caret left on the line after it.
  void insertImageBlock(String id, {required int rows}) {
    if (!isValidImageId(id)) return;
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
  }

  /// Makes the picture [delta] rows taller (or shorter), within
  /// [minImageRows]..[maxImageRows]. The caret stays on the picture.
  void resizeImage(ImageRun run, int delta) {
    final target = (run.rows + delta).clamp(minImageRows, maxImageRows);
    if (target == run.rows) return;
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
    selection = TextSelection.collapsed(offset: run.start);
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
