#ifndef FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_
#define FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_

#include <X11/Xlib.h>
#include <flutter_linux/flutter_linux.h>

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
  explicit ScreenGraph(FlTextureRegistrar* textures);
  ~ScreenGraph();

  ScreenGraph(const ScreenGraph&) = delete;
  ScreenGraph& operator=(const ScreenGraph&) = delete;

  FlValue* Enumerate();
  std::string RequestPermission();
  FlValue* BeginPick();
  void EndPick();
  void Indicate(const std::string& source_id);
  // Returns nullptr when Start is async (Wayland portal). Caller must not
  // respond; [pending] is g_object_ref'd until the portal answers.
  FlValue* Start(const std::string& source_id, bool include_audio, bool cursor,
                 bool motion, FlMethodCall* pending);
  void Stop();
  bool SetIncludeSystemAudio(bool enabled);
  void SetMotion(bool motion);
  void SetCursor(bool cursor);
  gboolean CopyPixels(const uint8_t** buffer, uint32_t* width, uint32_t* height,
                      GError** error);
  gboolean CopyPreviewPixels(const std::string& id, const uint8_t** buffer,
                             uint32_t* width, uint32_t* height, GError** error);
  FlValue* PortalStartedMap();

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

  struct Preview {
    FlPixelBufferTexture* texture = nullptr;
    std::vector<uint8_t> pixels;
    int width = 160;
    int height = 90;
  };

  bool IsWaylandOnly() const;
  void RefreshSources();
  void EnsureTexture();
  void CaptureLoop();
  bool CaptureX11(const Source& source, int out_w, int out_h,
                  std::vector<uint8_t>* dest);
  void EnsureDisplay();
  void CloseDisplay();
  void ClearPreviewsLocked();
  void ShowFrame(int x, int y, int w, int h);
  void HideFrame();
  bool StartPortal(FlMethodCall* pending, bool cursor, bool motion);
  void CancelPortal();

  FlTextureRegistrar* textures_;
  Display* display_ = nullptr;
  FlPixelBufferTexture* texture_ = nullptr;
  int64_t texture_id_ = -1;
  std::mutex mutex_;
  std::vector<uint8_t> front_;
  std::vector<Source> sources_;
  std::atomic<bool> running_{false};
  std::atomic<bool> motion_{false};
  std::atomic<bool> cursor_{true};
  std::thread capture_thread_;
  std::thread portal_thread_;
  struct PortalState;
  std::shared_ptr<PortalState> portal_state_;
  std::string send_id_;
  int send_width_ = 1280;
  int send_height_ = 720;
  Window frame_window_ = 0;
  std::unordered_map<std::string, std::unique_ptr<Preview>> previews_;
};

#endif  // FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_
