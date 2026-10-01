// Shared helpers for the Notebook ruled-grid policy tests: the Notebook theme
// and real font faces (Flutter's default test font, Ahem, has square metrics).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/lightweight_rich_editor.dart';

/// Must stay in sync with `lib/shared/widgets/formatting/ruled_rich_editor.dart`
/// in the Notebook app.
const notebookTheme = RichTextRenderTheme(
  baseFontSize: 16,
  lineHeight: 30,
  h1FontSize: 24,
  h2FontSize: 21,
  h3FontSize: 18,
);

String? fontsDir() {
  final candidates = [
    if (Platform.environment['FLUTTER_ROOT'] != null)
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts',
    'C:/Users/amadi/AndroidStudioPlugins/flutter/bin/cache/artifacts/material_fonts',
  ];
  for (final c in candidates) {
    if (Directory(c).existsSync()) return c;
  }
  return null;
}

Future<void> loadFontFamily(String family, List<(String, FontWeight, FontStyle)> faces, String dir) async {
  // One FontLoader can't express weight/style per face, so the faces are
  // registered under distinct weight/style via separate pubspec-less loads:
  // flutter_test's FontLoader only takes the family name, so bold/italic are
  // matched by the engine from the font's own OS/2 metadata.
  final loader = FontLoader(family);
  for (final face in faces) {
    final f = File('$dir/${face.$1}');
    if (!f.existsSync()) continue;
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
  }
  await loader.load();
}

Future<bool> loadSystemFont(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return false;
  try {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
    await loader.load();
    return true;
  } catch (_) {
    return false;
  }
}


/// Registers Roboto regular/bold/italic/bold-italic from the Flutter SDK under
/// the family name `Roboto`.
Future<void> loadRoboto() async {
  final dir = fontsDir();
  expect(dir, isNotNull, reason: 'Flutter material_fonts directory not found');
  await loadFontFamily('Roboto', [
    ('roboto-regular.ttf', FontWeight.normal, FontStyle.normal),
    ('roboto-bold.ttf', FontWeight.bold, FontStyle.normal),
    ('roboto-italic.ttf', FontWeight.normal, FontStyle.italic),
    ('roboto-bolditalic.ttf', FontWeight.bold, FontStyle.italic),
  ], dir!);
}

/// A non-linear text scaler, piecewise-linear through sampled (sp → scaled)
/// points like Android 14+'s system font scaling: small sizes grow more than
/// large ones. [android20] is the curve MEASURED on a device (Android 16) at
/// system font scale 2.0 — `16 → 28`, `24 → 36`, `30 → 38`.
class CurveTextScaler extends TextScaler {
  const CurveTextScaler(this.points, {this.name = 'curve'});

  final List<(double, double)> points;
  final String name;

  static const android20 = CurveTextScaler([
    (1, 2.0),
    (8, 16.0),
    (10, 20.0),
    (12, 24.0),
    (14, 26.0),
    (16, 28.0),
    (18, 30.0),
    (20, 34.0),
    (21, 34.5),
    (22, 35.0),
    (24, 36.0),
    (30, 38.0),
    (40, 46.857139587402344),
    (100, 100.0),
  ], name: 'android-2.0');

  /// Same shape with only [share] of the growth (a milder system font scale).
  static CurveTextScaler milder(double share, {String? name}) => CurveTextScaler([
    for (final p in android20.points) (p.$1, p.$1 + (p.$2 - p.$1) * share),
  ], name: name ?? 'android-x$share');

  @override
  double scale(double fontSize) {
    if (fontSize <= points.first.$1) return fontSize * points.first.$2 / points.first.$1;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (fontSize <= b.$1) return a.$2 + (b.$2 - a.$2) * (fontSize - a.$1) / (b.$1 - a.$1);
    }
    final last = points.last;
    return fontSize * last.$2 / last.$1;
  }

  // ignore: deprecated_member_use
  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) => other is CurveTextScaler && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'CurveTextScaler($name)';
}
