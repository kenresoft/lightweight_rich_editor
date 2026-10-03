// A white logo on nothing vanishes on a light page: such pictures get a contrasting card.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/images/rich_image_cache.dart';

Future<ui.Image> _picture({required Color ink, required bool onNothing}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (!onNothing) canvas.drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = const Color(0xFF888888));
  canvas.drawRect(const Rect.fromLTWH(20, 20, 24, 24), Paint()..color = ink);
  return recorder.endRecording().toImage(64, 64);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a white mark on nothing is measured as light and see-through', () async {
    final image = await _picture(ink: Colors.white, onNothing: true);
    final ink = await measureInk(image);
    expect(ink.transparentShare, greaterThan(0.5));
    expect(ink.luma, greaterThan(0.9));
    expect(ink.backdropFor(pageIsDark: false), isNotNull, reason: 'white on a light page needs a card');
    expect(ink.backdropFor(pageIsDark: true), isNull, reason: 'white on a dark page reads fine');
  });

  test('a black mark on nothing needs a card on a dark page only', () async {
    final ink = await measureInk(await _picture(ink: Colors.black, onNothing: true));
    expect(ink.luma, lessThan(0.1));
    expect(ink.backdropFor(pageIsDark: false), isNull);
    expect(ink.backdropFor(pageIsDark: true), isNotNull);
  });

  test('a photo (no see-through area) never gets a card', () async {
    final ink = await measureInk(await _picture(ink: Colors.white, onNothing: false));
    expect(ink.transparentShare, lessThan(0.12));
    expect(ink.backdropFor(pageIsDark: false), isNull);
    expect(ink.backdropFor(pageIsDark: true), isNull);
  });
}
