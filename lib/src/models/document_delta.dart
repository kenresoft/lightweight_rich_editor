import 'package:flutter/services.dart';
import 'text_attribute.dart';

/// Represents a delta change in the document state.
class DocumentDelta {
  final String? oldText;
  final String? newText;
  final List<TextAttribute>? removedAttributes;
  final List<TextAttribute>? addedAttributes;
  final TextSelection oldSelection;
  final TextSelection newSelection;

  DocumentDelta({
    this.oldText,
    this.newText,
    this.removedAttributes,
    this.addedAttributes,
    required this.oldSelection,
    required this.newSelection,
  });
}
