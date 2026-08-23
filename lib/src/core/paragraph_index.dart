import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';
import 'paragraph_record.dart';

/// Maintains one [ParagraphRecord] per paragraph in a document — the
/// paragraph-level counterpart to `AttributeStore`'s character-range
/// spans, for properties constant across a whole paragraph (e.g.
/// heading level) rather than varying within it (e.g. bold).
///
/// Records partition `[0, text.length]` with **no gaps** — every offset
/// belongs to exactly one record. Containment is inclusive on *both*
/// ends (`offset >= start && offset <= end`), unlike `AttributeStore`'s
/// span containment, because a paragraph boundary can't be left unowned.
/// The invariant `records[i].end + 1 == records[i+1].start` (the `'\n'`
/// occupies the one index between them) guarantees every offset maps to
/// exactly one record.
class ParagraphIndex {
  final List<ParagraphRecord> _records = [];

  /// Bumped on every mutation. A cheap cache-invalidation key for the
  /// renderer instead of diffing records on every rebuild.
  int _revision = 0;
  int get revision => _revision;

  ParagraphIndex._();

  /// Builds a fresh index by scanning `text` for `'\n'` characters.
  /// O(text.length) — never call this per-keystroke; use
  /// [applyInsertion]/[applyDeletion] for normal editing instead.
  factory ParagraphIndex.rebuild(String text) {
    final index = ParagraphIndex._();
    index._rebuildFrom(text);
    return index;
  }

  void _rebuildFrom(String text) {
    _records.clear();
    if (text.isEmpty) {
      _records.add(const ParagraphRecord(start: 0, end: 0));
      return;
    }
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        _records.add(ParagraphRecord(start: start, end: i));
        start = i + 1;
      }
    }
    _records.add(ParagraphRecord(start: start, end: text.length));
  }

  /// Every record, in document order. Read-only — mutate through the
  /// methods below, not this list.
  List<ParagraphRecord> get records => List.unmodifiable(_records);

  int get length => _records.length;

  /// Whether any paragraph in this index has a header level set. Used
  /// by the renderer to decide whether it can skip structural styling.
  bool get hasAnyHeader => _records.any((r) => r.headerLevel != null);

  /// The record containing `offset`, or `null` if `offset` is out of
  /// bounds. Linear scan.
  ParagraphRecord? paragraphAt(int offset) {
    for (final r in _records) {
      if (offset >= r.start && offset <= r.end) return r;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Structural edits — mirror AttributeStore.shiftForInsertion /
  // shiftForDeletion, called from the exact same EditingEngine choke
  // points, in the same order.
  // ---------------------------------------------------------------------

  /// Updates paragraph boundaries for `insertedText` inserted at
  /// `index`. If `insertedText` contains one or more `'\n'`, the record
  /// that absorbed the insertion is split at each newline; only the
  /// *first* resulting fragment keeps the original record's block
  /// metadata (header/alignment/direction never continue past a newline
  /// the user just typed).
  void applyInsertion(int index, String insertedText) {
    if (insertedText.isEmpty) return;
    final length = insertedText.length;

    final containingIndex = _records.indexWhere((r) => index >= r.start && index <= r.end);
    assert(containingIndex != -1,
    'ParagraphIndex.applyInsertion: no record contains offset $index');

    for (var i = 0; i < _records.length; i++) {
      if (i == containingIndex) continue;
      final r = _records[i];
      if (index <= r.start) {
        _records[i] = r.copyWith(start: r.start + length, end: r.end + length);
      }
    }

    final absorbing = _records[containingIndex];
    final grown = absorbing.copyWith(end: absorbing.end + length);

    if (!insertedText.contains('\n')) {
      _records[containingIndex] = grown;
      _revision++;
      return;
    }

    final fragments = <ParagraphRecord>[];
    var fragmentStart = grown.start;
    String? headerLevel = grown.headerLevel;
    ParagraphAlignment? alignment = grown.alignment;
    ParagraphTextDirection? textDirection = grown.textDirection;

    var searchOffset = 0;
    while (true) {
      final relative = insertedText.indexOf('\n', searchOffset);
      if (relative == -1) break;
      final newlineAbsolute = index + relative;
      fragments.add(ParagraphRecord(
        start: fragmentStart,
        end: newlineAbsolute,
        headerLevel: headerLevel,
        alignment: alignment,
        textDirection: textDirection,
      ));
      fragmentStart = newlineAbsolute + 1;
      headerLevel = null; // only the first fragment keeps block metadata
      alignment = null;
      textDirection = null;
      searchOffset = relative + 1;
    }
    fragments.add(ParagraphRecord(
      start: fragmentStart,
      end: grown.end,
      headerLevel: headerLevel,
      alignment: alignment,
      textDirection: textDirection,
    ));

    _records
      ..removeAt(containingIndex)
      ..insertAll(containingIndex, fragments);
    _revision++;
  }

  /// Updates paragraph boundaries for a deletion of `[start, end)`.
  /// Unlike an attribute span, a paragraph record can never simply
  /// vanish — paragraphs partition the whole document with no gaps — so
  /// every record whose separating `'\n'` falls inside the deleted range
  /// merges into one, keeping the *leftmost* record's block metadata.
  void applyDeletion(int start, int end) {
    if (end <= start) return;
    final deletedLength = end - start;

    final firstAffected = _records.indexWhere((r) => start >= r.start && start <= r.end);
    final lastAffected = _records.indexWhere((r) => end >= r.start && end <= r.end);
    assert(firstAffected != -1 && lastAffected != -1,
    'ParagraphIndex.applyDeletion: [$start, $end) out of bounds');

    final first = _records[firstAffected];
    final last = _records[lastAffected];
    final merged = ParagraphRecord(
      start: first.start,
      end: last.end - deletedLength,
      headerLevel: first.headerLevel,
      alignment: first.alignment,
      textDirection: first.textDirection,
    );

    final tail = _records
        .sublist(lastAffected + 1)
        .map((r) => r.copyWith(start: r.start - deletedLength, end: r.end - deletedLength))
        .toList(growable: false);

    _records
      ..removeRange(firstAffected, _records.length)
      ..add(merged)
      ..addAll(tail);
    _revision++;
  }

  // ---------------------------------------------------------------------
  // Block-level setters
  // ---------------------------------------------------------------------

  // Shared overlap condition for setHeaderLevel/recordsOverlapping. A
  // zero-width query (start == end) falls back to ParagraphRecord.contains
  // since the general half-open check can never match a zero-width record
  // (e.g. an empty paragraph) otherwise.
  bool _overlaps(ParagraphRecord r, int start, int end) {
    if (start == end) return r.contains(start);
    return r.start < end && r.end >= start;
  }

  /// Every record overlapping `[start, end)`.
  List<ParagraphRecord> recordsOverlapping(int start, int end) {
    return _records.where((r) => _overlaps(r, start, end)).toList(growable: false);
  }

  /// Sets `headerLevel` on every record overlapping `[start, end)`. A
  /// selection spanning multiple paragraphs sets all of them.
  void setHeaderLevel(int start, int end, String? headerLevel) {
    for (var i = 0; i < _records.length; i++) {
      final r = _records[i];
      if (_overlaps(r, start, end)) {
        _records[i] = r.copyWith(headerLevel: headerLevel, clearHeaderLevel: headerLevel == null);
      }
    }
    _revision++;
  }

  /// Sets `alignment` on every record overlapping `[start, end)`. Not
  /// yet reflected with a live rendering effect.
  void setAlignment(int start, int end, ParagraphAlignment? alignment) {
    for (var i = 0; i < _records.length; i++) {
      final r = _records[i];
      if (_overlaps(r, start, end)) {
        _records[i] = r.copyWith(alignment: alignment, clearAlignment: alignment == null);
      }
    }
    _revision++;
  }

  /// Sets `textDirection` on every record overlapping `[start, end)`.
  /// Not yet reflected with a live rendering effect.
  void setTextDirection(int start, int end, ParagraphTextDirection? textDirection) {
    for (var i = 0; i < _records.length; i++) {
      final r = _records[i];
      if (_overlaps(r, start, end)) {
        _records[i] = r.copyWith(textDirection: textDirection, clearTextDirection: textDirection == null);
      }
    }
    _revision++;
  }

  /// Restores block metadata on whichever current records overlap each
  /// `snapshot`'s original `[start, end)` — the shared undo primitive
  /// behind `ReplaceRangeCommand`/`ClearFormattingCommand`. Relies on the
  /// caller having already restored text to its pre-edit shape, so
  /// `snapshot.start`/`end` line up with a real current record again.
  void restoreBlockMetadata(List<ParagraphRecord> snapshots) {
    for (final snapshot in snapshots) {
      for (var i = 0; i < _records.length; i++) {
        final r = _records[i];
        if (_overlaps(r, snapshot.start, snapshot.end)) {
          _records[i] = r.copyWith(
            headerLevel: snapshot.headerLevel,
            clearHeaderLevel: snapshot.headerLevel == null,
            alignment: snapshot.alignment,
            clearAlignment: snapshot.alignment == null,
            textDirection: snapshot.textDirection,
            clearTextDirection: snapshot.textDirection == null,
          );
        }
      }
    }
    _revision++;
  }

  // ---------------------------------------------------------------------
  // Debug-only invariant check
  // ---------------------------------------------------------------------

  /// Asserts records are contiguous, gap-free, and span exactly
  /// `[0, textLength]`. Call via `assert(debugValidate(...))` so it's
  /// compiled out in release builds.
  bool debugValidate(int textLength) {
    if (_records.isEmpty) {
      throw StateError('ParagraphIndex: no records at all');
    }
    if (_records.first.start != 0) {
      throw StateError('ParagraphIndex: first record does not start at 0');
    }
    if (_records.last.end != textLength) {
      throw StateError(
          'ParagraphIndex: last record ends at ${_records.last.end}, expected $textLength');
    }
    for (var i = 0; i < _records.length - 1; i++) {
      if (_records[i].end + 1 != _records[i + 1].start) {
        throw StateError(
            'ParagraphIndex: gap or overlap between records $i and ${i + 1}: '
                '${_records[i]} then ${_records[i + 1]}');
      }
    }
    return true;
  }
}