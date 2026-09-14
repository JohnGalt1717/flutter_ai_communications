#ifndef FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_
#define FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_

#include <X11/Xlib.h>
#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <gtk/gtk.h>

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
  explicit ScreenGraph(FlTextureRegistrar* textures, GtkWidget* view = nullptr);
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
  struct PortalState;

 private:
  struct Source {
    std::string id;
    std::string name;
    std::string kind;
    std::string applicationName;
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
  void EnsureParentWindow();
  void CancelPortal();
  void FinishPortal(const char* status, const char* reason);
  void CompletePortalStart(GVariant* results, guint code);
  void FinishPortalStartIdle();
  bool InitEglDmaBuf();
  void DestroyEglDmaBuf();
  bool CopyDmaBufEgl(int fd, int width, int height, int stride, int offset,
                     std::vector<uint8_t>* dest);
  static void OnPortalStartResponse(GDBusConnection* connection,
                                    const gchar* sender,
                                    const gchar* object_path,
                                    const gchar* interface_name,
                                    const gchar* signal_name,
                                    GVariant* parameters, gpointer user_data);
  void StopPipeWire();
  bool ConnectPipeWire(int fd, uint32_t node_id, int width, int height);
  void CopyPipeWireFrame(const uint8_t* src, int src_w, int src_h, int stride,
                         uint32_t spa_format, const uint8_t* uv, int uv_stride);
  void MarkTexture();
  static void OnPwProcess(void* data);
  static void OnPwParamChanged(void* data, uint32_t id, const void* param);

  FlTextureRegistrar* textures_;
  GtkWidget* view_ = nullptr;
  std::string parent_window_;
  Display* display_ = nullptr;
  FlPixelBufferTexture* texture_ = nullptr;
  int64_t texture_id_ = -1;
  std::mutex mutex_;
  std::vector<uint8_t> front_;
  std::vector<uint8_t> back_;
  std::vector<uint8_t> upload_;
  std::atomic<bool> mark_pending_{false};
  std::vector<Source> sources_;
  std::atomic<bool> running_{false};
  std::atomic<bool> motion_{false};
  std::atomic<bool> cursor_{true};
  std::thread capture_thread_;
  std::thread portal_thread_;
  std::shared_ptr<PortalState> portal_state_;
  struct PwCapture;
  std::unique_ptr<PwCapture> pw_;
  std::string portal_session_;
  std::string send_id_;
  int send_width_ = 1280;
  int send_height_ = 720;
  Window frame_window_ = 0;
  std::unordered_map<std::string, std::unique_ptr<Preview>> previews_;
};

#endif  // FLUTTER_PLUGIN_LINUX_SCREEN_GRAPH_H_
