import 'attribute_store.dart';
import '../models/text_buffer.dart';
import '../models/text_attribute.dart';

/// The single owner of a note's content: its text and every formatting
/// span applied to it.
///
/// [EditorDocument] holds data and knows how to load, export, and
/// (de)serialize itself — nothing else. It does not know about cursors,
/// selections, undo history, or how to render a `TextSpan`; those belong
/// to the `EditingEngine`, `HistoryManager`, and `Renderer` respectively
/// (later phases). Keeping this class data-only is what makes it trivial
/// to unit test and safe to snapshot for undo/redo without dragging in
/// Flutter's widget layer.
class EditorDocument {
  TextBuffer _buffer;
  AttributeStore _attributes;

  EditorDocument({TextBuffer? buffer, AttributeStore? attributes})
      : _buffer = buffer ?? StringTextBuffer(),
        _attributes = attributes ?? AttributeStore() {
    _attributes.clampTo(_buffer.length);
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

  /// A read-only snapshot of every span currently in the document.
  List<TextAttribute> get attributes => _attributes.spans;

  /// Replaces the entire document in one step — used for loading a note
  /// and for undo/redo steps that restore a prior whole-text snapshot,
  /// as opposed to incremental inserts/deletes.
  void reset(String text, [List<TextAttribute> attributes = const []]) {
    _buffer = StringTextBuffer(text);
    _attributes = AttributeStore.fromSpans(attributes);
    _attributes.clampTo(_buffer.length);
    _attributes.optimize();
  }

  void clear() => reset('');

  Map<String, dynamic> toJson() => {
    'text': text,
    'attributes': _attributes.serialize(),
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
      'EditorDocument(${length} chars, ${_attributes.length} spans)';
}