import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/models/paragraph_alignment.dart';

void main() {
  group('EditorDocument JSON round-trip', () {
    test('headerLevel and alignment both survive toJson/fromJson together', () {
      final document = EditorDocument.fromText('Heading\nBody');
      document.paragraphs.setHeaderLevel(0, 7, 'h1');
      document.paragraphs.setAlignment(0, 7, ParagraphAlignment.center);

      final restored = EditorDocument.fromJson(document.toJson());

      expect(restored.text, 'Heading\nBody');
      expect(restored.paragraphs.paragraphAt(0)!.headerLevel, 'h1');
      expect(restored.paragraphs.paragraphAt(0)!.alignment, ParagraphAlignment.center);
      // "Body" paragraph had neither set.
      final bodyStart = 'Heading\n'.length;
      expect(restored.paragraphs.paragraphAt(bodyStart)!.headerLevel, isNull);
      expect(restored.paragraphs.paragraphAt(bodyStart)!.alignment, isNull);
    });

    test('a document with no header/alignment set round-trips unaffected', () {
      final document = EditorDocument.fromText('Plain text');
      final restored = EditorDocument.fromJson(document.toJson());
      expect(restored.text, 'Plain text');
      expect(restored.paragraphs.paragraphAt(0)!.headerLevel, isNull);
      expect(restored.paragraphs.paragraphAt(0)!.alignment, isNull);
    });
  });
}
