
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
    } catch (_) {
      // Degrading to plain text if the native plugin fails or isn't implemented.
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return (text: data?.text, html: null);
    }
  }

  /// Whether the clipboard holds a picture; reads no bytes.
  static Future<bool> hasImage() async {
    try {
      return await _channel.invokeMethod<bool>('hasImage') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The picture on the clipboard (a copied image, a screenshot), as its encoded
  /// bytes, or `null` when there is none or the platform cannot read one.
  static Future<Uint8List?> getImage() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('getImage');
      return (result == null || result.isEmpty) ? null : result;
    } catch (_) {
      return null;
    }
  }

  /// Copies text and optional HTML to the clipboard.
  static Future<void> setData({required String text, String? html}) async {
    try {
      await _channel.invokeMethod('setData', {
        'text': text,
        'html': html,
      });
    } catch (_) {
      // Fallback to standard Flutter API if native plugin fails.
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
