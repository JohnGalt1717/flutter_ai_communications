#include "include/flutter_ai_communications_linux/flutter_ai_communications_linux_plugin.h"

#include "camera_graph.h"
#include "screen_graph.h"

#include <cstring>
#include <memory>

typedef struct _FlutterAiCommunicationsLinuxPlugin
    FlutterAiCommunicationsLinuxPlugin;
typedef struct _FlutterAiCommunicationsLinuxPluginClass
    FlutterAiCommunicationsLinuxPluginClass;

struct _FlutterAiCommunicationsLinuxPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  CameraGraph* camera;
  ScreenGraph* screen;
};

struct _FlutterAiCommunicationsLinuxPluginClass {
  GObjectClass parent_class;
};

#define FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(obj)                            \
  (G_TYPE_CHECK_INSTANCE_CAST((obj),                                           \
                              flutter_ai_communications_linux_plugin_get_type(), \
                              FlutterAiCommunicationsLinuxPlugin))

G_DEFINE_TYPE(FlutterAiCommunicationsLinuxPlugin,
              flutter_ai_communications_linux_plugin,
              g_object_get_type())

static const gchar* ReadString(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "";
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return "";
  }
  return fl_value_get_string(value);
}

static int64_t ReadInt(FlValue* args, const char* key, int64_t fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return fl_value_get_int(value);
}

static bool ReadBool(FlValue* args, const char* key, bool fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

static void HandleMethodCall(FlMethodChannel* channel,
                             FlMethodCall* method_call,
                             gpointer user_data) {
  FlutterAiCommunicationsLinuxPlugin* self =
      FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "enumerateCameras") == 0) {
    g_autoptr(FlValue) cameras = self->camera->Enumerate();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(cameras));
  } else if (strcmp(method, "requestCameraPermission") == 0) {
    g_autoptr(FlValue) value =
        fl_value_new_string(self->camera->RequestPermission().c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "startCameraNative") == 0) {
    g_autoptr(FlValue) value = self->camera->Start(
        ReadString(args, "cameraId"),
        static_cast<int>(ReadInt(args, "width", 1280)),
        static_cast<int>(ReadInt(args, "height", 720)),
        static_cast<int>(ReadInt(args, "frameRate", 30)),
        ReadBool(args, "enabled", true), ReadBool(args, "muted", false));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "stopCameraNative") == 0) {
    self->camera->Stop();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "selectCameraNative") == 0) {
    self->camera->Select(ReadString(args, "cameraId"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setCameraEnabledNative") == 0) {
    self->camera->SetEnabled(ReadBool(args, "enabled", true));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setMuteVideoNative") == 0) {
    self->camera->SetMuted(ReadBool(args, "muted", false));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "cameraGraphStats") == 0) {
    g_autoptr(FlValue) value = self->camera->Stats();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "enumerateScreenSources") == 0) {
    g_autoptr(FlValue) value = self->screen->Enumerate();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "requestScreenPermission") == 0) {
    g_autoptr(FlValue) value =
        fl_value_new_string(self->screen->RequestPermission().c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "beginScreenPickNative") == 0) {
    g_autoptr(FlValue) value = self->screen->BeginPick();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "endScreenPickNative") == 0) {
    self->screen->EndPick();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "indicateScreenSourceNative") == 0) {
    self->screen->Indicate(ReadString(args, "sourceId"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "startScreenShareNative") == 0) {
    g_autoptr(FlValue) value = self->screen->Start(
        ReadString(args, "sourceId"),
        ReadBool(args, "includeSystemAudio", false),
        ReadBool(args, "cursor", true), ReadBool(args, "motion", false),
        method_call);
    if (value == nullptr) {
      return;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "stopScreenShareNative") == 0) {
    self->screen->Stop();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setIncludeSystemAudioNative") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(
        self->screen->SetIncludeSystemAudio(ReadBool(args, "enabled", false)));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "setScreenMotionNative") == 0) {
    self->screen->SetMotion(ReadBool(args, "motion", false));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setScreenCursorNative") == 0) {
    self->screen->SetCursor(ReadBool(args, "cursor", true));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
  (void)channel;
}

static void flutter_ai_communications_linux_plugin_dispose(GObject* object) {
  FlutterAiCommunicationsLinuxPlugin* self =
      FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(object);
  delete self->camera;
  self->camera = nullptr;
  delete self->screen;
  self->screen = nullptr;
  g_clear_object(&self->registrar);
  G_OBJECT_CLASS(flutter_ai_communications_linux_plugin_parent_class)
      ->dispose(object);
}

static void flutter_ai_communications_linux_plugin_class_init(
    FlutterAiCommunicationsLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose =
      flutter_ai_communications_linux_plugin_dispose;
}

static void flutter_ai_communications_linux_plugin_init(
    FlutterAiCommunicationsLinuxPlugin* self) {
  self->registrar = nullptr;
  self->camera = nullptr;
  self->screen = nullptr;
}

void flutter_ai_communications_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  FlutterAiCommunicationsLinuxPlugin* plugin =
      FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(g_object_new(
          flutter_ai_communications_linux_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  plugin->camera = new CameraGraph(
      fl_plugin_registrar_get_texture_registrar(registrar));
  plugin->screen = new ScreenGraph(
      fl_plugin_registrar_get_texture_registrar(registrar));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_ai_communications/methods", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, HandleMethodCall, g_object_ref(plugin), g_object_unref);
  g_object_unref(plugin);
}
