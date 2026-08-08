import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_rich_editor/src/utils/url_detector.dart';

void main() {
  group('detectAllUrls', () {
    test('detects multiple URLs in text', () {
      final text = 'Check google.com and https://flutter.dev for info';
      final results = detectAllUrls(text);
      expect(results, hasLength(2));
      expect(results[0].href, 'https://google.com');
      expect(results[1].href, 'https://flutter.dev');
    });

    test('detects URL at start and end of string', () {
      final text = 'google.com is cool';
      final results = detectAllUrls(text);
      expect(results.single.href, 'https://google.com');
      
      final text2 = 'go to google.com';
      final results2 = detectAllUrls(text2);
      expect(results2.single.href, 'https://google.com');
    });

    test('ignores non-URLs', () {
      final text = 'This is just a.test and another.thing';
      final results = detectAllUrls(text);
      expect(results, isEmpty);
    });

    test('handles punctuation after URL', () {
      final text = 'Visit google.com. and then...';
      final results = detectAllUrls(text);
      expect(results.single.href, 'https://google.com');
      expect(results.single.end, 16); // offset of '.' after google.com
    });
  });
}
