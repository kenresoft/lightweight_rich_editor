import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/utils/clamp_int.dart';

void main() {
  test('returns value unchanged when within bounds', () {
    expect(clampInt(5, 0, 10), 5);
  });

  test('clamps below the minimum', () {
    expect(clampInt(-3, 0, 10), 0);
  });

  test('clamps above the maximum', () {
    expect(clampInt(15, 0, 10), 10);
  });

  test('returns an int, not num — this is the whole point of the function', () {
    final result = clampInt(15, 0, 10);
    expect(result, isA<int>());
  });

  test('handles min == max', () {
    expect(clampInt(7, 3, 3), 3);
  });
}