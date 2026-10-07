#include "include/flutter_ai_communications_linux/flutter_ai_communications_linux_plugin.h"

#include "camera_graph.h"
#include "screen_graph.h"

#include <atomic>
#include <cstring>
#include <memory>
#include <string>
#include <thread>

typedef struct _FlutterAiCommunicationsLinuxPlugin
    FlutterAiCommunicationsLinuxPlugin;
typedef struct _FlutterAiCommunicationsLinuxPluginClass
    FlutterAiCommunicationsLinuxPluginClass;

struct _FlutterAiCommunicationsLinuxPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  CameraGraph* camera;
  ScreenGraph* screen;
  FlEventChannel* events;
  gboolean events_listening;
  std::shared_ptr<std::atomic<bool>>* dispatch_alive;
  GtkWidget* window;
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

static void SetMarksAllowed(FlutterAiCommunicationsLinuxPlugin* plugin,
                            bool allowed) {
  if (plugin->camera != nullptr) {
    plugin->camera->SetMarksAllowed(allowed);
  }
  if (plugin->screen != nullptr) {
    plugin->screen->SetMarksAllowed(allowed);
  }
}

static gboolean OnWindowMap(GtkWidget*, GdkEventAny*, gpointer data) {
  FlutterAiCommunicationsLinuxPlugin* plugin =
      FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(data);
  SetMarksAllowed(plugin, true);
  if (plugin->camera != nullptr) {
    plugin->camera->RefreshTexture();
  }
  if (plugin->screen != nullptr) {
    plugin->screen->RefreshTexture();
  }
  return FALSE;
}

static gboolean OnWindowUnmap(GtkWidget*, GdkEventAny*, gpointer data) {
  SetMarksAllowed(FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(data), false);
  return FALSE;
}

static void EmitProcessorUnavailable(
    FlutterAiCommunicationsLinuxPlugin* plugin) {
  if (plugin == nullptr || plugin->dispatch_alive == nullptr ||
      !(*plugin->dispatch_alive)->load()) {
    return;
  }
  struct Emit {
    FlutterAiCommunicationsLinuxPlugin* plugin;
    std::shared_ptr<std::atomic<bool>> alive;
  };
  auto* emit = new Emit{plugin, *plugin->dispatch_alive};
  g_object_ref(plugin);
  g_idle_add(
      [](gpointer data) -> gboolean {
        auto* emit = static_cast<Emit*>(data);
        FlutterAiCommunicationsLinuxPlugin* plugin = emit->plugin;
        if (emit->alive->load() && plugin->events_listening &&
            plugin->events != nullptr) {
          g_autoptr(FlValue) map = fl_value_new_map();
          fl_value_set_string_take(map, "type",
                                   fl_value_new_string("processor"));
          fl_value_set_string_take(map, "payload",
                                   fl_value_new_string("unavailable"));
          fl_event_channel_send(plugin->events, map, nullptr, nullptr);
        }
        g_object_unref(plugin);
        delete emit;
        return G_SOURCE_REMOVE;
      },
      emit);
}

static FlMethodErrorResponse* OnEventsListen(FlEventChannel*, FlValue*,
                                             gpointer user_data) {
  FlutterAiCommunicationsLinuxPlugin* plugin =
      FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(user_data);
  plugin->events_listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* OnEventsCancel(FlEventChannel*, FlValue*,
                                             gpointer user_data) {
  FlutterAiCommunicationsLinuxPlugin* plugin =
      FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(user_data);
  plugin->events_listening = FALSE;
  return nullptr;
}

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

static void RespondOnIdle(FlutterAiCommunicationsLinuxPlugin* plugin,
                          FlMethodCall* method_call, FlValue* value) {
  struct Done {
    FlutterAiCommunicationsLinuxPlugin* plugin;
    FlMethodCall* pending;
    FlValue* map;
  };
  auto* done = new Done{plugin, method_call, fl_value_ref(value)};
  g_idle_add(
      [](gpointer data) -> gboolean {
        auto* done = static_cast<Done*>(data);
        g_autoptr(FlMethodResponse) response =
            FL_METHOD_RESPONSE(fl_method_success_response_new(done->map));
        fl_method_call_respond(done->pending, response, nullptr);
        g_object_unref(done->pending);
        fl_value_unref(done->map);
        g_object_unref(done->plugin);
        delete done;
        return G_SOURCE_REMOVE;
      },
      done);
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
    g_object_ref(method_call);
    g_object_ref(self);
    std::thread([self, method_call]() {
      g_autoptr(FlValue) cameras = self->camera->Enumerate();
      RespondOnIdle(self, method_call, cameras);
    }).detach();
    return;
  } else if (strcmp(method, "requestCameraPermission") == 0) {
    g_object_ref(method_call);
    g_object_ref(self);
    std::thread([self, method_call]() {
      g_autoptr(FlValue) value =
          fl_value_new_string(self->camera->RequestPermission().c_str());
      RespondOnIdle(self, method_call, value);
    }).detach();
    return;
  } else if (strcmp(method, "startCameraNative") == 0) {
    const std::string camera_id = ReadString(args, "cameraId");
    const int width = static_cast<int>(ReadInt(args, "width", 1280));
    const int height = static_cast<int>(ReadInt(args, "height", 720));
    const int frame_rate = static_cast<int>(ReadInt(args, "frameRate", 30));
    const bool enabled = ReadBool(args, "enabled", true);
    const bool muted = ReadBool(args, "muted", false);
    self->camera->EnsureTexture();
    g_object_ref(method_call);
    g_object_ref(self);
    std::thread([self, method_call, camera_id, width, height, frame_rate,
                 enabled, muted]() {
      g_autoptr(FlValue) value = self->camera->Start(
          camera_id, width, height, frame_rate, enabled, muted);
      RespondOnIdle(self, method_call, value);
    }).detach();
    return;
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
  } else if (strcmp(method, "setVideoProcessorNative") == 0) {
    g_autoptr(FlValue) value =
        fl_value_new_string(self->camera->SetProcessor(args).c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
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
  if (self->dispatch_alive != nullptr) {
    (*self->dispatch_alive)->store(false);
  }
  if (self->window != nullptr) {
    g_signal_handlers_disconnect_by_data(self->window, self);
    self->window = nullptr;
  }
  if (self->camera != nullptr) {
    self->camera->SetOnProcessorUnavailable(nullptr);
  }
  delete self->camera;
  self->camera = nullptr;
  delete self->screen;
  self->screen = nullptr;
  self->events_listening = FALSE;
  g_clear_object(&self->events);
  g_clear_object(&self->registrar);
  delete self->dispatch_alive;
  self->dispatch_alive = nullptr;
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
  self->events = nullptr;
  self->events_listening = FALSE;
  self->dispatch_alive = nullptr;
  self->window = nullptr;
}

void flutter_ai_communications_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  FlutterAiCommunicationsLinuxPlugin* plugin =
      FLUTTER_AI_COMMUNICATIONS_LINUX_PLUGIN(g_object_new(
          flutter_ai_communications_linux_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  plugin->dispatch_alive = new std::shared_ptr<std::atomic<bool>>(
      std::make_shared<std::atomic<bool>>(true));
  const auto dispatch_alive = *plugin->dispatch_alive;
  plugin->camera = new CameraGraph(
      fl_plugin_registrar_get_texture_registrar(registrar));
  plugin->camera->SetOnProcessorUnavailable(
      [plugin, dispatch_alive]() {
        if (!dispatch_alive->load()) {
          return;
        }
        EmitProcessorUnavailable(plugin);
      });
  plugin->screen = new ScreenGraph(
      fl_plugin_registrar_get_texture_registrar(registrar),
      fl_plugin_registrar_get_view(registrar));
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view != nullptr) {
    GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
    plugin->window = top;
    g_signal_connect_object(top, "map-event", G_CALLBACK(OnWindowMap), plugin,
                            static_cast<GConnectFlags>(0));
    g_signal_connect_object(top, "unmap-event", G_CALLBACK(OnWindowUnmap),
                            plugin, static_cast<GConnectFlags>(0));
    SetMarksAllowed(plugin, gtk_widget_get_mapped(top) != FALSE);
  }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_ai_communications/methods", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, HandleMethodCall, g_object_ref(plugin), g_object_unref);
  plugin->events = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_ai_communications/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->events, OnEventsListen,
                                       OnEventsCancel, plugin, nullptr);
  g_object_unref(plugin);
}
