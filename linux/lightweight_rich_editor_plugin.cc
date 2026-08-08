#include "include/lightweight_rich_editor/lightweight_rich_editor_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include <map>

#define LIGHTWEIGHT_RICH_EDITOR_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), lightweight_rich_editor_plugin_get_type(), \
                              LightweightRichEditorPlugin))

struct _LightweightRichEditorPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(LightweightRichEditorPlugin, lightweight_rich_editor_plugin, g_object_get_type())

static void lightweight_rich_editor_plugin_handle_method_call(
    LightweightRichEditorPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getData") == 0) {
    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);

    gchar* text = gtk_clipboard_wait_for_text(clipboard);

    // Gtk usually doesn't have a direct "wait_for_html" but we can request targets
    // For simplicity in this manual plugin, we'll return text and null html for now
    // or use wait_for_contents if needed.

    FlValue* result = fl_value_new_map();
    fl_value_set_string_take(result, "text", text ? fl_value_new_string(text) : fl_value_new_null());
    fl_value_set_string_take(result, "html", fl_value_new_null());

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    if (text) g_free(text);
  } else if (strcmp(method, "setData") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* text_val = fl_value_lookup_string(args, "text");

    if (text_val && fl_value_get_type(text_val) == FL_VALUE_TYPE_STRING) {
        GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
        gtk_clipboard_set_text(clipboard, fl_value_get_string(text_val), -1);
    }

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void lightweight_rich_editor_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(lightweight_rich_editor_plugin_parent_class)->dispose(object);
}

static void lightweight_rich_editor_plugin_class_init(LightweightRichEditorPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = lightweight_rich_editor_plugin_dispose;
}

static void lightweight_rich_editor_plugin_init(LightweightRichEditorPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  LightweightRichEditorPlugin* plugin = LIGHTWEIGHT_RICH_EDITOR_PLUGIN(user_data);
  lightweight_rich_editor_plugin_handle_method_call(plugin, method_call);
}

void lightweight_rich_editor_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  LightweightRichEditorPlugin* plugin = LIGHTWEIGHT_RICH_EDITOR_PLUGIN(
      g_object_new(lightweight_rich_editor_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "com.kenresoft.lightweight_rich_editor/rich_clipboard",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
