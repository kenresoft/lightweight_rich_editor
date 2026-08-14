import 'attribute_store.dart';
import 'paragraph_block.dart';
import 'paragraph_index.dart';
import '../models/attribute_type.dart';
import '../models/paragraph_alignment.dart';
import '../models/paragraph_text_direction.dart';
import '../models/text_buffer.dart';
import '../models/text_attribute.dart';

/// The single owner of a note's content: its text and every formatting
/// span applied to it.
///
/// [EditorDocument] holds data and knows how to load, export, and
/// (de)serialize itself — nothing else. It does not know about cursors,
/// selections, undo history, or how to render a `TextSpan`; those belong
/// to the `EditingEngine`, `HistoryManager`, and `Renderer` respectively.
/// Keeping this class data-only is what makes it trivial to unit test
/// and safe to snapshot for undo/redo without dragging in Flutter's
/// widget layer.
class EditorDocument {
  TextBuffer _buffer;
  AttributeStore _attributes;

  // Assigned in the constructor body, once `_buffer` definitely exists —
  // building this from `buffer ?? StringTextBuffer()` directly in the
  // initializer list would evaluate that expression a second time,
  // independently of the one assigned to `_buffer`, constructing a
  // different (if harmlessly empty) buffer instance for a null `buffer`
  // argument.
  late ParagraphIndex _paragraphs;

  EditorDocument({TextBuffer? buffer, AttributeStore? attributes})
      : _buffer = buffer ?? StringTextBuffer(),
        _attributes = attributes ?? AttributeStore() {
    _attributes.clampTo(_buffer.length);
    _paragraphs = ParagraphIndex.rebuild(_buffer.text);
    _seedParagraphBlockMetadata();
  }

  /// Builds a document from plain text and a set of spans, clamping and
  /// optimizing the spans against the given text so the result is always
  /// internally consistent regardless of where the input came from.
  factory EditorDocument.fromText(
      String text, [
        List<TextAttribute> attributes = const [],
      ]) {
    final buffer = StringTextBuffer(text);
    final store = AttributeStore.fromSpans(attributes);
    store.clampTo(buffer.length);
    store.optimize();
    return EditorDocument(buffer: buffer, attributes: store);
  }

  String get text => _buffer.text;

  int get length => _buffer.length;

  bool get isEmpty => _buffer.isEmpty;

  /// The underlying storage. Exposed for the `EditingEngine`, which is
  /// the only other component permitted to call its mutating methods
  /// directly — everything else should treat text as read-only via
  /// [text].
  TextBuffer get buffer => _buffer;

  /// The span store. Exposed for the `EditingEngine` and `Renderer` for
  /// the same reason.
  AttributeStore get attributeStore => _attributes;

  /// The paragraph-level counterpart to [attributeStore] — see
  /// `ParagraphIndex`'s own doc comment for what it's for and why it's a
  /// separate mechanism from character-range attributes. Header
  /// formatting is read from here everywhere it's live: `TextSpanRenderer`,
  /// undo, and toolbar state (`RichEditorController.isAttributeActive`/
  /// `activeAttributeValue`) all read/write [paragraphs], never
  /// [attributeStore], for header. `AttributeType.header` stays in the
  /// enum, but purely as the interchange format at the boundary with
  /// HTML/Markdown/clipboard — see its own doc comment for why that's a
  /// deliberate, permanent split rather than something to eliminate.
  ParagraphIndex get paragraphs => _paragraphs;

  /// The fully-resolved [ParagraphBlock] (list type, checked state,
  /// indent level, header level) for the paragraph containing `offset`,
  /// or `null` if `offset` is out of bounds. The one canonical place to
  /// ask "what kind of block is this" — see [ParagraphBlock]'s own doc
  /// comment for why this replaces callers hand-deriving the same
  /// properties themselves.
  ParagraphBlock? blockAt(int offset) {
    final record = _paragraphs.paragraphAt(offset);
    if (record == null) return null;
    return ParagraphBlock.derive(record, text);
  }

  /// A read-only snapshot of every span currently in the document.
  List<TextAttribute> get attributes => _attributes.spans;

  /// Every attribute needed to represent this document as a flat,
  /// ranged list — the shape `HtmlExporter`/`MarkdownExporter` and
  /// `ClipboardManager` expect, and have expected all along; nothing
  /// about their own code needs to change for this. Inline attributes
  /// (bold, italic, links, ...) come straight from [attributeStore].
  /// Header and alignment spans are synthesized fresh from [paragraphs]
  /// instead — [paragraphs] is their only live representation (see
  /// [paragraphs]'s doc comment); [attributeStore] can still contain a
  /// stale header/align span (from paste, or from
  /// [_seedParagraphBlockMetadata]) that nothing keeps in sync with
  /// further edits, so reading either directly from there would risk
  /// exporting something no longer true.
  ///
  /// Empty paragraphs never contribute a span here — same
  /// zero-width-span-is-dropped rule `AttributeStore.insert` already
  /// follows, kept consistent rather than exported as something
  /// `attributeStore`-based export could never have produced.
  List<TextAttribute> exportAttributes() {
    final inline = _attributes.spans.where(
      (a) => a.type != AttributeType.header && a.type != AttributeType.align && a.type != AttributeType.textDirection,
    );
    final headers = _paragraphs.records.where((r) => r.headerLevel != null && r.end > r.start).map(
          (r) => TextAttribute(start: r.start, end: r.end, type: AttributeType.header, value: r.headerLevel),
    );
    final alignments = _paragraphs.records.where((r) => r.alignment != null && r.end > r.start).map(
          (r) => TextAttribute(start: r.start, end: r.end, type: AttributeType.align, value: r.alignment!.name),
    );
    final textDirections = _paragraphs.records.where((r) => r.textDirection != null && r.end > r.start).map(
          (r) => TextAttribute(start: r.start, end: r.end, type: AttributeType.textDirection, value: r.textDirection!.name),
    );
    return [...inline, ...headers, ...alignments, ...textDirections];
  }

  /// Replaces the entire document in one step — used for loading a note
  /// and for undo/redo steps that restore a prior whole-text snapshot,
  /// as opposed to incremental inserts/deletes.
  void reset(String text, [List<TextAttribute> attributes = const []]) {
    _buffer = StringTextBuffer(text);
    _attributes = AttributeStore.fromSpans(attributes);
    _attributes.clampTo(_buffer.length);
    _attributes.optimize();
    _paragraphs = ParagraphIndex.rebuild(_buffer.text);
    _seedParagraphBlockMetadata();
  }

  void clear() => reset('');

  /// Seeds `_paragraphs`' `headerLevel`/`alignment` fields from whatever
  /// `AttributeType.header`/`AttributeType.align` spans are already in
  /// `_attributes` — needed because [ParagraphIndex.rebuild] only knows
  /// about `'\n'` positions, not formatting.
  ///
  /// This isn't specifically about *old* saved notes — there's no
  /// legacy on-disk data this library needs to worry about right now.
  /// It's the general contract for [EditorDocument.fromText]/[fromJson]:
  /// whatever the caller passes as initial `attributes` may contain a
  /// header or align entry (that's still a completely ordinary shape —
  /// see `AttributeType.header`'s own doc comment on why they remain the
  /// interchange format), and without this, that metadata would silently
  /// go nowhere — sitting inertly in [attributeStore], which nothing
  /// reads either from anymore, instead of being reflected in
  /// [paragraphs], which is what actually drives rendering/export/
  /// toolbar state. Cheap and self-contained enough that there's no real
  /// cost to keeping this correct even though nothing in this app's
  /// current usage happens to exercise it today.
  ///
  /// Empty paragraphs are skipped, matching `AttributeStore.insert`'s
  /// own zero-width-span-is-dropped rule — an empty paragraph can never
  /// have had a real header/align span to seed from in the first place.
  void _seedParagraphBlockMetadata() {
    for (final record in _paragraphs.records) {
      if (record.start >= record.end) continue;
      final headerSpans = _attributes.findAt(record.start, type: AttributeType.header);
      if (headerSpans.isNotEmpty) {
        _paragraphs.setHeaderLevel(record.start, record.end, headerSpans.first.value as String?);
      }
      final alignSpans = _attributes.findAt(record.start, type: AttributeType.align);
      if (alignSpans.isNotEmpty) {
        final value = alignSpans.first.value as String?;
        _paragraphs.setAlignment(record.start, record.end, value == null ? null : ParagraphAlignment.values.byName(value));
      }
      final directionSpans = _attributes.findAt(record.start, type: AttributeType.textDirection);
      if (directionSpans.isNotEmpty) {
        final value = directionSpans.first.value as String?;
        _paragraphs.setTextDirection(
          record.start,
          record.end,
          value == null ? null : ParagraphTextDirection.values.byName(value),
        );
      }
    }
  }

  /// Serializes this document. `'attributes'` comes from
  /// [exportAttributes], not `_attributes.serialize()` directly — this
  /// is what makes a newly-set header actually persist: nothing writes
  /// a new `AttributeType.header` `TextAttribute` into [attributeStore]
  /// when a heading is set via `EditingEngine.setHeaderLevel` (see
  /// [paragraphs]'s doc comment), so serializing [attributeStore] alone
  /// would silently drop any heading set since this note was loaded. The
  /// on-disk *shape* is unchanged — still a flat list of `TextAttribute`
  /// JSON objects, header included.
  Map<String, dynamic> toJson() => {
    'text': text,
    'attributes': exportAttributes().map((a) => a.toJson()).toList(growable: false),
  };

  factory EditorDocument.fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String? ?? '';
    final rawAttributes = json['attributes'] as List<dynamic>? ?? const [];
    return EditorDocument.fromText(
      text,
      rawAttributes
          .map((j) => TextAttribute.fromJson(j as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  @override
  String toString() =>
      'EditorDocument($length chars, ${_attributes.length} spans, ${_paragraphs.length} paragraphs)';
}