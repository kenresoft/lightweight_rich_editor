import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  group('RichEditorController autolink', () {
    test('updates existing link target when text is edited', () {
      final controller = RichEditorController();
      
      // Type google.com 
      controller.value = const TextEditingValue(
        text: 'Visit google.com ',
        selection: TextSelection.collapsed(offset: 17),
      );
      
      expect(controller.document.attributes.any((a) => a.type == AttributeType.link), isTrue);
      final initialLink = controller.document.attributes.firstWhere((a) => a.type == AttributeType.link);
      expect(initialLink.value, 'https://google.com');

      // Edit Visit google.com | to Visit google.org|
      controller.value = const TextEditingValue(
        text: 'Visit google.org',
        selection: TextSelection.collapsed(offset: 16),
      );
      
      // Type a space to trigger autolink update
      controller.value = const TextEditingValue(
        text: 'Visit google.org ',
        selection: TextSelection.collapsed(offset: 17),
      );

      final updatedLink = controller.document.attributes.firstWhere((a) => a.type == AttributeType.link);
      expect(updatedLink.value, 'https://google.org');
    });
  });
}
