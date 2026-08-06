import '../models/text_attribute.dart';

/// Stores rich text for internal copy/paste to preserve formatting.
class RichClipboard {
  RichClipboard._();

  static final RichClipboard instance = RichClipboard._();

  String plainText = '';
  List<TextAttribute> attributes = [];

  void setData(String text, List<TextAttribute> attrs) {
    plainText = text;
    attributes = attrs.map((a) => a.copyWith()).toList();
  }
}
