import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class LightweightRichEditorWeb {
  static void registerWith(dynamic registrar) {
    // Web plugin registration (`web_plugin_registrant.dart`) runs before
    // `main()` calls `runApp()`, so the binary messenger this channel
    // needs doesn't exist yet unless something initializes the binding
    // first. `ensureInitialized()` is idempotent — safe to call here even
    // though the app's own `main()` doesn't (and shouldn't need to) call
    // it again — and this is the exact fix Flutter's own assertion
    // message names for "setMethodCallHandler before the binary
    // messenger has been initialized".
    WidgetsFlutterBinding.ensureInitialized();
    final channel = MethodChannel(
      'com.kenresoft.lightweight_rich_editor/rich_clipboard',
      const StandardMethodCodec(),
    );
    final pluginInstance = LightweightRichEditorWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getData':
        return await _getClipboardData();
      case 'setData':
        return await _setClipboardData(call.arguments);
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'lightweight_rich_editor for web doesn\'t implement \'${call.method}\'',
        );
    }
  }

  Future<void> _setClipboardData(dynamic arguments) async {
    try {
      final Map<dynamic, dynamic> args = arguments;
      final text = args['text'] as String?;
      final html = args['html'] as String?;

      if (text == null) return;

      final clipboard = web.window.navigator.clipboard;
      
      final Map<String, JSAny> dataMap = {};
      dataMap['text/plain'] = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: 'text/plain'));
      if (html != null) {
        dataMap['text/html'] = web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html'));
      }

      final item = web.ClipboardItem(dataMap.jsify() as JSObject);
      await clipboard.write([item].toJS).toDart;
    } catch (e) {
      if (arguments['text'] != null) {
        await web.window.navigator.clipboard.writeText(arguments['text'] as String).toDart;
      }
    }
  }

  Future<Map<String, String?>> _getClipboardData() async {
    try {
      final clipboard = web.window.navigator.clipboard;
      final itemsPromise = _readClipboard(clipboard);
      final items = await itemsPromise.toDart;
      
      String? plainText;
      String? htmlText;

      final dartItems = items.toDart;
      for (var i = 0; i < dartItems.length; i++) {
        final item = dartItems[i];
        final types = item.types.toDart;
        
        for (var j = 0; j < types.length; j++) {
          final typeString = types[j].toDart;
          if (typeString == 'text/plain') {
            final blob = await item.getType('text/plain').toDart;
            plainText = await _readBlobAsText(blob);
          } else if (typeString == 'text/html') {
            final blob = await item.getType('text/html').toDart;
            htmlText = await _readBlobAsText(blob);
          }
        }
      }

      return {
        'text': plainText,
        'html': htmlText,
      };
    } catch (e) {
      try {
        final textPromise = web.window.navigator.clipboard.readText();
        final text = await textPromise.toDart;
        return {'text': text.toDart, 'html': null};
      } catch (_) {
        return {'text': null, 'html': null};
      }
    }
  }

  Future<String> _readBlobAsText(web.Blob blob) async {
    final textPromise = blob.text();
    final text = await textPromise.toDart;
    return text.toDart;
  }
}

@JS('navigator.clipboard.read')
external JSPromise<JSArray<web.ClipboardItem>> _readClipboard(web.Clipboard clipboard);
