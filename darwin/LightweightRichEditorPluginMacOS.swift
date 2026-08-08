#if os(macOS)
import FlutterMacOS
import AppKit

public class LightweightRichEditorPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.kenresoft.lightweight_rich_editor/rich_clipboard", binaryMessenger: registrar.messenger)
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
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    var items: [NSPasteboardItem] = []
    let item = NSPasteboardItem()

    if let text = text {
      item.setString(text, forType: .string)
    }

    if let html = html {
      item.setString(html, forType: .html)
    }

    items.append(item)
    pasteboard.writeObjects(items)
  }

  private func getClipboardData() -> [String: String?] {
    let pasteboard = NSPasteboard.general

    let plainText = pasteboard.string(forType: .string)
    let htmlText = pasteboard.string(forType: .html)

    return [
      "text": plainText,
      "html": htmlText
    ]
  }
}
#endif
