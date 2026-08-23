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
/// selections, undo history, or rendering; those belong to the
/// `EditingEngine`, `HistoryManager`, and `Renderer` respectively.
class EditorDocument {
  TextBuffer _buffer;
  AttributeStore _attributes;

  // Assigned in the constructor body: building this from
  // `buffer ?? StringTextBuffer()` directly in the initializer list would
  // construct a second, separate empty buffer for a null `buffer` arg.
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

  /// The underlying storage. Only [EditingEngine] should call its
  /// mutating methods directly — everything else should treat text as
  /// read-only via [text].
  TextBuffer get buffer => _buffer;

  /// The span store, exposed for `EditingEngine` and `Renderer`.
  AttributeStore get attributeStore => _attributes;

  /// The paragraph-level counterpart to [attributeStore]. Header,
  /// alignment, and text-direction formatting are read/written here, not
  /// [attributeStore] — `AttributeType.header`/`align`/`textDirection`
  /// remain only as the interchange format at HTML/Markdown/clipboard
  /// boundaries.
  ParagraphIndex get paragraphs => _paragraphs;

  /// The fully-resolved [ParagraphBlock] (list type, checked state,
  /// indent level, header level) for the paragraph containing `offset`,
  /// or `null` if out of bounds.
  ParagraphBlock? blockAt(int offset) {
    final record = _paragraphs.paragraphAt(offset);
    if (record == null) return null;
    return ParagraphBlock.derive(record, text);
  }

  /// A read-only snapshot of every span currently in the document.
  List<TextAttribute> get attributes => _attributes.spans;

  /// Every attribute needed to represent this document as a flat, ranged
  /// list — the shape exporters and the clipboard manager expect. Inline
  /// attributes come straight from [attributeStore]; header, alignment,
  /// and text-direction spans are synthesized fresh from [paragraphs],
  /// since [attributeStore] may hold stale entries nothing keeps in sync.
  /// Empty paragraphs never contribute a span.
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

  // Seeds `_paragraphs`' headerLevel/alignment/textDirection fields from
  // whatever matching spans are already in `_attributes` — needed because
  // ParagraphIndex.rebuild only knows about '\n' positions, not
  // formatting. Without this, header/align/direction passed into
  // fromText/fromJson would sit inertly in attributeStore, which nothing
  // reads for those types once loaded.
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
  /// [exportAttributes], not the raw attribute store, so header/alignment/
  /// text-direction changes made since load are included.
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