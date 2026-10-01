// The field's scroll area ends `paddingBottom` above the editor's bottom edge.
// Text scrolling through that gap must be drawn whole, not cut mid-glyph at an
// invisible edge above the bottom bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  testWidgets('the text field does not clip at its own bottom, and the extended clip covers the padding gap', (tester) async {
    final c = RichEditorController(text: List.generate(80, (i) => 'line $i').join('\n'));
    final sc = ScrollController();
    addTearDown(c.dispose);
    addTearDown(sc.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RichTextEditor(controller: c, scrollController: sc, autofocus: false)),
    ));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.clipBehavior, Clip.none, reason: 'the field itself must not cut text at its bottom edge');

    final clip = tester.widget<ClipRect>(find.ancestor(of: find.byType(TextField), matching: find.byType(ClipRect)).first);
    final fieldSize = tester.getSize(find.byType(TextField));
    final rect = clip.clipper!.getClip(fieldSize);
    expect(rect.bottom, RichEditorStyle.standard.paddingBottom + fieldSize.height);
    expect(rect.top, 0, reason: 'the top edge is unchanged');
  });
}
