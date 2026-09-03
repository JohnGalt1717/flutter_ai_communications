#ifndef FLUTTER_PLUGIN_WINDOWS_SCREEN_GRAPH_H_
#define FLUTTER_PLUGIN_WINDOWS_SCREEN_GRAPH_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/texture_registrar.h>

#include "wgc_capture.h"

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

class ScreenGraph {
 public:
  ScreenGraph(flutter::TextureRegistrar* textures, HWND flutter_window);
  ~ScreenGraph();

  ScreenGraph(const ScreenGraph&) = delete;
  ScreenGraph& operator=(const ScreenGraph&) = delete;

  flutter::EncodableList Enumerate();
  std::string RequestPermission();
  flutter::EncodableMap BeginPick();
  void EndPick();
  void Indicate(const std::string& source_id);
  flutter::EncodableMap Start(const std::string& source_id, bool include_audio,
                              bool cursor, bool motion);
  void Stop();
  bool SetIncludeSystemAudio(bool enabled);
  void SetMotion(bool motion);
  void SetCursor(bool cursor);

 private:
  struct Source {
    std::string id;
    std::string name;
    std::string kind;
    RECT bounds{};
    HWND hwnd = nullptr;
    HMONITOR monitor = nullptr;
  };

  struct Preview {
    std::unique_ptr<flutter::TextureVariant> texture;
    std::unique_ptr<FlutterDesktopPixelBuffer> pixel_buffer;
    std::vector<uint8_t> pixels;
    int64_t texture_id = -1;
    int width = 160;
    int height = 90;
  };

  void RefreshSources();
  void ClearPreviewsLocked();
  void EnsureSendTexture();
  void CaptureLoop();
  void CaptureSourceLocked(const Source& source, int out_w, int out_h,
                           std::vector<uint8_t>* dest, bool cursor);
  bool StartWgcLocked(const Source& source, bool cursor);
  void ShowFrame(const RECT& bounds);
  void HideFrame();
  static LRESULT CALLBACK FrameWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                       LPARAM lparam);
  const FlutterDesktopPixelBuffer* CopySendBuffer(size_t width, size_t height);
  const FlutterDesktopPixelBuffer* CopyPreviewBuffer(Preview* preview);

  flutter::TextureRegistrar* textures_;
  HWND flutter_window_;
  HWND frame_window_ = nullptr;
  ATOM frame_class_ = 0;
  std::mutex mutex_;
  std::vector<Source> sources_;
  std::unordered_map<std::string, std::unique_ptr<Preview>> previews_;
  std::unique_ptr<flutter::TextureVariant> send_texture_;
  std::unique_ptr<FlutterDesktopPixelBuffer> send_pixel_buffer_;
  std::vector<uint8_t> send_front_;
  int64_t send_texture_id_ = -1;
  int send_width_ = 1280;
  int send_height_ = 720;
  std::atomic<bool> running_{false};
  std::atomic<bool> cursor_{true};
  std::atomic<bool> motion_{false};
  std::thread capture_thread_;
  std::string send_id_;
  WgcCapture wgc_;
};

#endif  // FLUTTER_PLUGIN_WINDOWS_SCREEN_GRAPH_H_
