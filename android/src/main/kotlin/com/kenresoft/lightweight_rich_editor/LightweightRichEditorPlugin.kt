package com.kenresoft.lightweight_rich_editor

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

class LightweightRichEditorPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private val mainHandler = Handler(Looper.getMainLooper())
  // A single background thread for reading picture bytes, so a large picture
  // never blocks the UI thread.
  private val io = Executors.newSingleThreadExecutor()

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.kenresoft.lightweight_rich_editor/rich_clipboard")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getData" -> result.success(getClipboardData())
      "getImage" -> getImage(result)
      "hasImage" -> result.success(hasImage())
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

  // Whether the clipboard holds a picture (no bytes are read).
  private fun hasImage(): Boolean {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = clipboard.primaryClip ?: return false
    if (clip.description.hasMimeType("image/*")) return true
    for (i in 0 until clip.itemCount) {
      val uri = clip.getItemAt(i).uri ?: continue
      val type = try { context.contentResolver.getType(uri) } catch (e: Exception) { null }
      if (type != null && type.startsWith("image/")) return true
    }
    return false
  }

  // The picture on the clipboard (a copied image, a screenshot), as its encoded
  // bytes; null when there is none. Looks for a content URI whose type is an
  // image, reads it off the UI thread, and gives up past [MAX_IMAGE_BYTES].
  private fun getImage(result: Result) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = clipboard.primaryClip
    var uri: Uri? = null
    if (clip != null) {
      for (i in 0 until clip.itemCount) {
        val candidate = clip.getItemAt(i).uri ?: continue
        val type = try { context.contentResolver.getType(candidate) } catch (e: Exception) { null }
        if (type != null && type.startsWith("image/")) {
          uri = candidate
          break
        }
      }
    }
    if (uri == null) {
      result.success(null)
      return
    }
    val source = uri
    io.execute {
      var bytes: ByteArray? = null
      try {
        context.contentResolver.openInputStream(source)?.use { input ->
          val out = java.io.ByteArrayOutputStream()
          val buffer = ByteArray(64 * 1024)
          var total = 0
          while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            total += n
            if (total > MAX_IMAGE_BYTES) { out.reset(); break }
            out.write(buffer, 0, n)
          }
          if (total <= MAX_IMAGE_BYTES) bytes = out.toByteArray()
        }
      } catch (e: Exception) {
        bytes = null
      }
      val data = bytes
      mainHandler.post { result.success(if (data == null || data.isEmpty()) null else data) }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    io.shutdown()
  }

  companion object {
    private const val MAX_IMAGE_BYTES = 25 * 1024 * 1024
  }
}
