// Renders the example at phone size and writes PNGs to screenshots/raw.
// Run from the example folder: flutter test integration_test/screenshots_test.dart -d windows
import 'dart:io';
import 'dart:ui' as ui;

import 'package:example/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _ratio = 2.75;

// Roboto from the Flutter SDK, so the capture matches what Android shows.
const _fontDir =
    'C:/Users/amadi/AndroidStudioPlugins/flutter/bin/cache/artifacts/material_fonts';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    // A 2:1 phone-shaped canvas: 392 x 784 logical pixels, 1078 x 2156 px.
    tester.view.physicalSize = const Size(392 * _ratio, 784 * _ratio);
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.runAsync(() async {
      Future<ByteData> load(String file) async =>
          ByteData.sublistView(await File('$_fontDir/$file').readAsBytes());
      final roboto = FontLoader('Roboto')
        ..addFont(load('roboto-regular.ttf'))
        ..addFont(load('roboto-medium.ttf'))
        ..addFont(load('roboto-bold.ttf'))
        ..addFont(load('roboto-italic.ttf'));
      await roboto.load();
    });

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          tester.renderObject(find.byType(RepaintBoundary).first)
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: _ratio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('screenshots/raw/$name.png');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    Future<void> scrollTo(double dy) async {
      await tester.dragFrom(const Offset(196, 600), Offset(0, dy));
      await tester.pumpAndSettle();
    }

    Future<void> toTop() async {
      for (var i = 0; i < 6; i++) {
        await scrollTo(500);
      }
    }

    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The caret starts at the end of the note, so go to the top first.
    await toTop();
    await shot('01-page');

    // Tap the picture to select it and show its size bar.
    await tester.tapAt(const Offset(196, 520));
    await tester.pumpAndSettle();
    await shot('02-picture');

    // Lists and code at the bottom, with the link bar open. Tap a line of
    // text first so the picture is no longer selected.
    await tester.tapAt(const Offset(196, 350));
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.dragFrom(const Offset(196, 700), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.tapAt(const Offset(196, 673));
    await tester.pumpAndSettle();
    await shot('03-code-link');

    await toTop();
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'camera');
    await shot('04-find');

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pumpAndSettle();
    await toTop();
    // Put the caret on the heading so the old find match is not left selected.
    await tester.tapAt(const Offset(330, 145));
    await tester.pumpAndSettle();
    await shot('05-dark');
    debugDefaultTargetPlatformOverride = null;
  });
}
