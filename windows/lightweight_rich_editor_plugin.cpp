#include "lightweight_rich_editor/lightweight_rich_editor_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <memory>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

class LightweightRichEditorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  LightweightRichEditorPlugin();

  virtual ~LightweightRichEditorPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  EncodableValue GetClipboardData();
  void SetClipboardData(const EncodableMap &args);
};

// static
void LightweightRichEditorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.kenresoft.lightweight_rich_editor/rich_clipboard",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<LightweightRichEditorPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

LightweightRichEditorPlugin::LightweightRichEditorPlugin() {}

LightweightRichEditorPlugin::~LightweightRichEditorPlugin() {}

void LightweightRichEditorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getData") == 0) {
    result->Success(GetClipboardData());
  } else if (method_call.method_name().compare("setData") == 0) {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) {
        SetClipboardData(*args);
        result->Success();
    } else {
        result->Error("Bad Arguments", "Expected map");
    }
  } else {
    result->NotImplemented();
  }
}

EncodableValue LightweightRichEditorPlugin::GetClipboardData() {
  EncodableMap result;
  result[EncodableValue("text")] = EncodableValue();
  result[EncodableValue("html")] = EncodableValue();

  if (!OpenClipboard(nullptr)) return EncodableValue(result);

  // Text
  HANDLE hData = ::GetClipboardData(CF_UNICODETEXT);
  if (hData != nullptr) {
    wchar_t* pszText = static_cast<wchar_t*>(GlobalLock(hData));
    if (pszText != nullptr) {
        std::wstring ws(pszText);
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, &ws[0], (int)ws.size(), NULL, 0, NULL, NULL);
        std::string strTo(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, &ws[0], (int)ws.size(), &strTo[0], size_needed, NULL, NULL);
        result[EncodableValue("text")] = EncodableValue(strTo);
        GlobalUnlock(hData);
    }
  }

  // HTML
  UINT cfHtml = RegisterClipboardFormatA("HTML Format");
  hData = ::GetClipboardData(cfHtml);
  if (hData != nullptr) {
    char* pszText = static_cast<char*>(GlobalLock(hData));
    if (pszText != nullptr) {
        result[EncodableValue("html")] = EncodableValue(std::string(pszText));
        GlobalUnlock(hData);
    }
  }

  CloseClipboard();
  return EncodableValue(result);
}

void LightweightRichEditorPlugin::SetClipboardData(const EncodableMap &args) {
    if (!OpenClipboard(nullptr)) return;
    EmptyClipboard();

    auto it_text = args.find(EncodableValue("text"));
    if (it_text != args.end() && !it_text->second.IsNull()) {
        std::string text = std::get<std::string>(it_text->second);
        int wchars_num = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, NULL, 0);
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, wchars_num * sizeof(wchar_t));
        wchar_t* pMem = static_cast<wchar_t*>(GlobalLock(hMem));
        MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, pMem, wchars_num);
        GlobalUnlock(hMem);
        ::SetClipboardData(CF_UNICODETEXT, hMem);
    }

    auto it_html = args.find(EncodableValue("html"));
    if (it_html != args.end() && !it_html->second.IsNull()) {
        std::string fragment = std::get<std::string>(it_html->second);

        std::string html = "<html><body><!--StartFragment-->" + fragment + "<!--EndFragment--></body></html>";

        std::string header =
            "Version:0.9\r\n"
            "StartHTML:00000000\r\n"
            "EndHTML:00000000\r\n"
            "StartFragment:00000000\r\n"
            "EndFragment:00000000\r\n";

        int startHTML = (int)header.length();
        int startFragment = (int)(header.length() + std::string("<html><body><!--StartFragment-->").length());
        int endFragment = (int)(startFragment + fragment.length());
        int endHTML = (int)(header.length() + html.length());

        std::stringstream ss;
        ss << "Version:0.9\r\n"
           << "StartHTML:" << std::setw(8) << std::setfill('0') << startHTML << "\r\n"
           << "EndHTML:" << std::setw(8) << std::setfill('0') << endHTML << "\r\n"
           << "StartFragment:" << std::setw(8) << std::setfill('0') << startFragment << "\r\n"
           << "EndFragment:" << std::setw(8) << std::setfill('0') << endFragment << "\r\n"
           << html;

        std::string final_payload = ss.str();
        UINT cfHtml = RegisterClipboardFormatA("HTML Format");
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, final_payload.size() + 1);
        char* pMem = static_cast<char*>(GlobalLock(hMem));
        memcpy(pMem, final_payload.c_str(), final_payload.size() + 1);
        GlobalUnlock(hMem);
        ::SetClipboardData(cfHtml, hMem);
    }

    CloseClipboard();
}

}  // namespace

void LightweightRichEditorPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  LightweightRichEditorPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
