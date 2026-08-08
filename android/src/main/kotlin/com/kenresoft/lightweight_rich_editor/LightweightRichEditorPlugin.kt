package com.kenresoft.lightweight_rich_editor

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class LightweightRichEditorPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var context: Context

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.kenresoft.lightweight_rich_editor/rich_clipboard")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getData" -> result.success(getClipboardData())
      "setData" -> {
        val text = call.argument<String>("text")
        val html = call.argument<String>("html")
        setData(text, html)
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun setData(text: String?, html: String?) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = if (html != null) {
      android.content.ClipData.newHtmlText("Label", text, html)
    } else {
      android.content.ClipData.newPlainText("Label", text)
    }
    clipboard.setPrimaryClip(clip)
  }

  private fun getClipboardData(): Map<String, String?> {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = clipboard.primaryClip
    
    var plainText: String? = null
    var htmlText: String? = null

    if (clip != null && clip.itemCount > 0) {
      val item = clip.getItemAt(0)
      plainText = item.text?.toString()
      htmlText = item.htmlText
      
      // Some apps put HTML in the plain text flavor but label it as HTML.
      // But usually, item.htmlText is the standard place for it.
    }
    
    return mapOf(
      "text" to plainText,
      "html" to htmlText
    )
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
