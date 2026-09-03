#ifndef FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_
#define FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class ScreenGraph {
 public:
  explicit ScreenGraph(FlTextureRegistrar* textures);
  ~ScreenGraph();

  ScreenGraph(const ScreenGraph&) = delete;
  ScreenGraph& operator=(const ScreenGraph&) = delete;

  FlValue* Enumerate();
  std::string RequestPermission();
  FlValue* BeginPick();
  void EndPick();
  void Indicate(const std::string& source_id);
  FlValue* Start(const std::string& source_id, bool include_audio, bool cursor,
                 bool motion);
  void Stop();
  bool SetIncludeSystemAudio(bool enabled);
  void SetMotion(bool motion);
  void SetCursor(bool cursor);
  gboolean CopyPixels(const uint8_t** buffer, uint32_t* width, uint32_t* height,
                      GError** error);

 private:
  struct Source {
    std::string id;
    std::string name;
    std::string kind;
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
    unsigned long window = 0;
  };

  bool IsWaylandOnly() const;
  void RefreshSources();
  void EnsureTexture();
  void CaptureLoop();
  bool CaptureX11(const Source& source, int out_w, int out_h);

  FlTextureRegistrar* textures_;
  FlPixelBufferTexture* texture_ = nullptr;
  int64_t texture_id_ = -1;
  std::mutex mutex_;
  std::vector<uint8_t> front_;
  std::vector<Source> sources_;
  std::atomic<bool> running_{false};
  std::atomic<bool> motion_{false};
  std::thread capture_thread_;
  std::string send_id_;
  int send_width_ = 1280;
  int send_height_ = 720;
};

#endif  // FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_
