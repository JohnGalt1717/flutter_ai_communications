#include "include/flutter_ai_communications_windows/flutter_ai_communications_windows_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "camera_graph.h"

namespace {

int ReadInt(const flutter::EncodableMap& args, const char* key, int fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return *i32;
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*i64);
  }
  return fallback;
}

bool ReadBool(const flutter::EncodableMap& args, const char* key, bool fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return fallback;
}

std::string ReadString(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return {};
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return {};
}

class FlutterAiCommunicationsWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<FlutterAiCommunicationsWindowsPlugin>(
        registrar);
    registrar->AddPlugin(std::move(plugin));
  }

  explicit FlutterAiCommunicationsWindowsPlugin(
      flutter::PluginRegistrarWindows* registrar)
      : camera_(registrar->texture_registrar()) {
    channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "flutter_ai_communications/methods",
            &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  ~FlutterAiCommunicationsWindowsPlugin() override = default;

  FlutterAiCommunicationsWindowsPlugin(
      const FlutterAiCommunicationsWindowsPlugin&) = delete;
  FlutterAiCommunicationsWindowsPlugin& operator=(
      const FlutterAiCommunicationsWindowsPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string& method = call.method_name();
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    flutter::EncodableMap empty;
    const flutter::EncodableMap& map = args != nullptr ? *args : empty;
    if (method == "enumerateCameras") {
      result->Success(flutter::EncodableValue(camera_.Enumerate()));
      return;
    }
    if (method == "requestCameraPermission") {
      result->Success(flutter::EncodableValue(camera_.RequestPermission()));
      return;
    }
    if (method == "startCameraNative") {
      result->Success(flutter::EncodableValue(camera_.Start(
          ReadString(map, "cameraId"), ReadInt(map, "width", 1280),
          ReadInt(map, "height", 720), ReadInt(map, "frameRate", 30),
          ReadBool(map, "enabled", true), ReadBool(map, "muted", false))));
      return;
    }
    if (method == "stopCameraNative") {
      camera_.Stop();
      result->Success();
      return;
    }
    if (method == "selectCameraNative") {
      camera_.Select(ReadString(map, "cameraId"));
      result->Success();
      return;
    }
    if (method == "setCameraEnabledNative") {
      camera_.SetEnabled(ReadBool(map, "enabled", true));
      result->Success();
      return;
    }
    if (method == "setMuteVideoNative") {
      camera_.SetMuted(ReadBool(map, "muted", false));
      result->Success();
      return;
    }
    if (method == "cameraGraphStats") {
      result->Success(flutter::EncodableValue(camera_.Stats()));
      return;
    }
    result->NotImplemented();
  }

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  CameraGraph camera_;
};

}  // namespace

void FlutterAiCommunicationsWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterAiCommunicationsWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
