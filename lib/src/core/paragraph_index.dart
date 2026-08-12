import 'paragraph_record.dart';

/// Maintains one [ParagraphRecord] per paragraph in a document — the
/// paragraph-level counterpart to `AttributeStore`'s character-range
/// spans. See the block-architecture design notes for why these are two
/// different mechanisms: `AttributeStore` fits properties that vary
/// *within* a paragraph (bold covers these 8 characters); this fits
/// properties that are constant *across* a whole paragraph (this
/// paragraph is a heading).
///
/// Deliberately minimal for this phase: [ParagraphRecord.headerLevel]
/// is the only populated field. Header is this structure's sole *live*
/// representation — `AttributeType.header` still exists in the enum,
/// but purely as the interchange format at the boundary with
/// HTML/Markdown/clipboard (`HtmlExporter`/`MarkdownExporter`/
/// `MarkdownImporter`/`HtmlImporter`/`EditingEngine.pasteRich`); nothing
/// in the live editing/rendering/undo/toolbar path writes an
/// `AttributeType.header` span anymore. See the block-architecture
/// design notes for the full migration history.
///
/// Records partition `[0, text.length]` with **no gaps** — every offset
/// belongs to exactly one record. That's the one place this
/// deliberately diverges from `AttributeStore`'s conventions:
/// containment here is inclusive on *both* ends
/// (`offset >= start && offset <= end`), not exclusive on the start side
/// like `AttributeStore.shiftForInsertion`. `AttributeStore` can afford
/// ambiguity at a span boundary because unformatted gaps between spans
/// are allowed; a paragraph boundary can't be left unowned, so this
/// can't use the same convention. The invariant
/// `records[i].end + 1 == records[i+1].start` (the `'\n'` itself
/// occupies the one index between them) guarantees no offset ever
/// satisfies both a record's `<= end` and the next record's `>= start`
/// — every offset maps to exactly one record, always.
class ParagraphIndex {
  final List<ParagraphRecord> _records = [];

  /// Bumped on every mutation — mirrors `AttributeStore.revision`
  /// exactly, same purpose: a cheap cache-invalidation key for
  /// `TextSpanRenderer` instead of diffing records on every rebuild.
  int _revision = 0;
  int get revision => _revision;

  ParagraphIndex._();

  /// Builds a fresh index by scanning `text` for `'\n'` characters.
  /// O(text.length) — a one-time cost, same as `AttributeStore.clampTo`
  /// accepts for load/reset. Never call this per-keystroke;
  /// [applyInsertion]/[applyDeletion] exist specifically so this isn't
  /// necessary during normal editing.
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
  /// bounds. Linear scan for now — matches `AttributeStore`'s own
  /// unoptimized-by-design posture (`TextBuffer`'s own doc comment: "we
  /// do not optimize this prematurely"); a sorted-offset binary search
  /// is a drop-in upgrade later if profiling ever calls for it, without
  /// changing this method's contract.
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
  /// *first* resulting fragment keeps the original record's
  /// `headerLevel` — every fragment after a split newline starts with
  /// `headerLevel: null`. This mirrors the existing, already-shipped
  /// rule that header formatting confines to the paragraph it started in
  /// and never continues past a newline the user just typed
  /// (`EditingEngine._confineParagraphScopedAttributes`), generalized
  /// from one newline to N — a multi-paragraph paste only keeps the
  /// header on whichever fragment contains what preceded the insertion
  /// point.
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

    var searchOffset = 0;
    while (true) {
      final relative = insertedText.indexOf('\n', searchOffset);
      if (relative == -1) break;
      final newlineAbsolute = index + relative;
      fragments.add(ParagraphRecord(start: fragmentStart, end: newlineAbsolute, headerLevel: headerLevel));
      fragmentStart = newlineAbsolute + 1;
      headerLevel = null; // only the first fragment keeps it
      searchOffset = relative + 1;
    }
    fragments.add(ParagraphRecord(start: fragmentStart, end: grown.end, headerLevel: headerLevel));

    _records
      ..removeAt(containingIndex)
      ..insertAll(containingIndex, fragments);
    _revision++;
  }

  /// Updates paragraph boundaries for a deletion of `[start, end)` —
  /// mirrors `AttributeStore.shiftForDeletion`, but *merges* rather than
  /// drops: unlike an attribute span (which can simply vanish if the
  /// text it covered is deleted), a paragraph record can never disappear
  /// without transferring its position in the document to a surviving
  /// neighbor, because paragraphs partition the whole document with no
  /// gaps.
  ///
  /// Every record whose separating `'\n'` falls inside the deleted range
  /// merges into one. The surviving record keeps the *leftmost* (first)
  /// of the merged records' `headerLevel` — mirrors the existing rule
  /// that header formatting doesn't survive past a paragraph break,
  /// generalized to "and therefore doesn't survive that break being
  /// deleted either."
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

  /// The overlap condition shared by [setHeaderLevel] and
  /// [recordsOverlapping] — defined once so a caller snapshotting
  /// records for undo (see `SetHeaderLevelCommand`) is guaranteed to
  /// select exactly the same records a `setHeaderLevel` call is about to
  /// mutate, rather than risking the two conditions drifting apart if
  /// one were ever edited without the other.
  bool _overlaps(ParagraphRecord r, int start, int end) => r.start < end && r.end >= start;

  /// Every record overlapping `[start, end)`.
  List<ParagraphRecord> recordsOverlapping(int start, int end) {
    return _records.where((r) => _overlaps(r, start, end)).toList(growable: false);
  }

  /// Sets `headerLevel` on every record overlapping `[start, end)`.
  ///
  /// A selection spanning multiple paragraphs sets all of them — this is
  /// header's sole live representation now (`AttributeType.header` is no
  /// longer written to; see `EditingEngine.setHeaderLevel` and the
  /// block-architecture design notes), matching the behavior the old
  /// `AttributeStore`-based path had: applying header to a
  /// multi-paragraph selection always affected every paragraph in that
  /// selection uniformly, never just one.
  void setHeaderLevel(int start, int end, String? headerLevel) {
    for (var i = 0; i < _records.length; i++) {
      final r = _records[i];
      if (_overlaps(r, start, end)) {
        _records[i] = r.copyWith(headerLevel: headerLevel, clearHeaderLevel: headerLevel == null);
      }
    }
    _revision++;
  }

  // ---------------------------------------------------------------------
  // Debug-only invariant check
  // ---------------------------------------------------------------------

  /// Asserts records are contiguous, gap-free, and span exactly
  /// `[0, textLength]` — same role as the length assertion already in
  /// `RichEditorController.buildTextSpan`, applied to this structure
  /// instead. Call from inside an `assert(() { ...; return true; }())`
  /// (or `assert(debugValidate(...))`, since this already returns
  /// `true`) so it's compiled out entirely in release builds.
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