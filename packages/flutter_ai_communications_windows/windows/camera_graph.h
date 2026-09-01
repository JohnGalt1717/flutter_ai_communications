#ifndef FLUTTER_PLUGIN_WINDOWS_CAMERA_GRAPH_H_
#define FLUTTER_PLUGIN_WINDOWS_CAMERA_GRAPH_H_

#include <flutter/encodable_value.h>
#include <flutter/texture_registrar.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct IMFSourceReader;
struct IMFMediaSource;

class CameraGraph {
 public:
  explicit CameraGraph(flutter::TextureRegistrar* textures);
  ~CameraGraph();

  CameraGraph(const CameraGraph&) = delete;
  CameraGraph& operator=(const CameraGraph&) = delete;

  flutter::EncodableList Enumerate();
  std::string RequestPermission();
  flutter::EncodableMap Start(const std::string& camera_id,
                              int width,
                              int height,
                              int frame_rate,
                              bool enabled,
                              bool muted);
  void Stop();
  void Select(const std::string& camera_id);
  void SetEnabled(bool enabled);
  void SetMuted(bool muted);
  flutter::EncodableMap Stats() const;

 private:
  struct Mode {
    int width = 1280;
    int height = 720;
    int fps = 30;
    int PixelCount() const { return width * height; }
  };

  void EnsureTexture();
  void StopCapture();
  bool StartCapture(const std::string& camera_id, int width, int height,
                    int frame_rate);
  void CaptureLoop();
  void CopySample(void* sample);
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);
  void FillBlackLocked();
  bool PickNativeMode(IMFSourceReader* reader, const Mode& requested,
                      Mode* out);
  bool ConfigureRgb32(IMFSourceReader* reader, const Mode& native);
  void ReadCurrentFormat(IMFSourceReader* reader);
  static Mode Nearest(const Mode& requested, const std::vector<Mode>& modes);
  static std::string FacingFor(const std::string& name,
                               const std::string& symlink);

  flutter::TextureRegistrar* textures_;
  std::unique_ptr<flutter::TextureVariant> texture_;
  std::unique_ptr<FlutterDesktopPixelBuffer> pixel_buffer_;
  int64_t texture_id_ = -1;
  std::mutex mutex_;
  std::vector<uint8_t> front_;
  std::atomic<bool> running_{false};
  std::atomic<bool> muted_{false};
  std::atomic<bool> enabled_{true};
  std::atomic<int64_t> frame_count_{0};
  std::atomic<int64_t> live_frames_{0};
  std::thread capture_thread_;
  IMFSourceReader* reader_ = nullptr;
  IMFMediaSource* source_ = nullptr;
  std::string camera_id_;
  int width_ = 1280;
  int height_ = 720;
  int frame_rate_ = 30;
  int request_width_ = 1280;
  int request_height_ = 720;
  int request_frame_rate_ = 30;
};

#endif  // FLUTTER_PLUGIN_WINDOWS_CAMERA_GRAPH_H_
