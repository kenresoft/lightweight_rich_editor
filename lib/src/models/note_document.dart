import 'text_attribute.dart';

/// Represents a full rich text document, including text and its attributes.
class NoteDocument {
  /// The plain text content of the document.
  final String text;

  /// The list of rich text attributes applied to the text.
  final List<TextAttribute> attributes;

  /// Creates a [NoteDocument].
  NoteDocument({required this.text, required this.attributes});

  /// Converts this document to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'attributes': attributes.map((a) => a.toJson()).toList(),
    };
  }

  /// Creates a [NoteDocument] from a JSON-compatible map.
  factory NoteDocument.fromJson(Map<String, dynamic> json) {
    return NoteDocument(
      text: json['text'] as String,
      attributes: (json['attributes'] as List)
          .map((a) => TextAttribute.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}
