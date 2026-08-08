import 'package:flutter/services.dart';

/// Internal plugin interface for rich clipboard access.
class RichClipboardPlatform {
  static const MethodChannel _channel = MethodChannel('com.kenresoft.lightweight_rich_editor/rich_clipboard');

  /// Fetches the current clipboard content in both plain text and HTML.
  static Future<({String? text, String? html})> getData() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getData');
      if (result == null) return (text: null, html: null);
      
      return (
        text: result['text'] as String?,
        html: result['html'] as String?,
      );
    } on PlatformException catch (e) {
      // Degrading to plain text if the native plugin fails or isn't implemented.
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return (text: data?.text, html: null);
    }
  }

  /// Copies text and optional HTML to the clipboard.
  static Future<void> setData({required String text, String? html}) async {
    try {
      await _channel.invokeMethod('setData', {
        'text': text,
        'html': html,
      });
    } on PlatformException catch (_) {
      // Fallback to standard Flutter API if native plugin fails.
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
