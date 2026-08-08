#if os(iOS)
import Flutter
import UIKit
import MobileCoreServices

public class LightweightRichEditorPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.kenresoft.lightweight_rich_editor/rich_clipboard", binaryMessenger: registrar.messenger())
    let instance = LightweightRichEditorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch (call.method) {
    case "getData":
      result(getClipboardData())
    case "setData":
      let args = call.arguments as! [String: Any]
      let text = args["text"] as? String
      let html = args["html"] as? String
      setData(text: text, html: html)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setData(text: String?, html: String?) {
    let pasteboard = UIPasteboard.general

    if let html = html, let text = text {
      pasteboard.setItems([
        [
          kUTTypeHTML as String: html,
          kUTTypePlainText as String: text
        ]
      ])
    } else if let text = text {
      pasteboard.string = text
    }
  }

  private func getClipboardData() -> [String: String?] {
    let pasteboard = UIPasteboard.general

    var plainText: String? = pasteboard.string
    var htmlText: String? = nil

    if pasteboard.contains(pasteboardTypes: ["public.html"]) {
      if let data = pasteboard.data(forPasteboardType: "public.html") {
         htmlText = String(data: data, encoding: .utf8)
      }
    }

    return [
      "text": plainText,
      "html": htmlText
    ]
  }
}
#endif
