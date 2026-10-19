import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

void main() {
  testWidgets('shows the editor and toggles dark mode', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(LightweightRichEditor), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pump();

    expect(find.byIcon(Icons.light_mode), findsOneWidget);
  });
}
