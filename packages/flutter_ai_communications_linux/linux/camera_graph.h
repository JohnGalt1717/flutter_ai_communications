#ifndef FLUTTER_PLUGIN_LINUX_CAMERA_GRAPH_H_
#define FLUTTER_PLUGIN_LINUX_CAMERA_GRAPH_H_

#include <flutter_linux/flutter_linux.h>
#include <linux/videodev2.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct MappedBuffer {
  void* start = nullptr;
  size_t length = 0;
};

class CameraGraph {
 public:
  explicit CameraGraph(FlTextureRegistrar* textures);
  ~CameraGraph();

  CameraGraph(const CameraGraph&) = delete;
  CameraGraph& operator=(const CameraGraph&) = delete;

  FlValue* Enumerate();
  std::string RequestPermission();
  FlValue* Start(const std::string& camera_id,
                 int width,
                 int height,
                 int frame_rate,
                 bool enabled,
                 bool muted);
  void Stop();
  void Select(const std::string& camera_id);
  void SetEnabled(bool enabled);
  void SetMuted(bool muted);
  FlValue* Stats() const;
  gboolean CopyPixels(const uint8_t** buffer,
                      uint32_t* width,
                      uint32_t* height,
                      GError** error);

 private:
  void EnsureTexture();
  void StopCapture();
  bool StartCapture(const std::string& camera_id, int width, int height,
                    int frame_rate);
  void CaptureLoop();
  void ConvertFrame(const uint8_t* src);
  void FillBlackLocked();
  bool TrySetFormat(uint32_t fourcc, int width, int height, v4l2_format* out);
  static std::string FacingFor(const std::string& name,
                               const std::string& bus_info);

  FlTextureRegistrar* textures_;
  FlPixelBufferTexture* texture_ = nullptr;
  int64_t texture_id_ = -1;
  std::mutex mutex_;
  std::vector<uint8_t> front_;
  std::vector<uint8_t> display_;
  std::atomic<bool> running_{false};
  std::atomic<bool> muted_{false};
  std::atomic<bool> enabled_{true};
  std::atomic<int64_t> frame_count_{0};
  std::atomic<int64_t> live_frames_{0};
  std::thread capture_thread_;
  int fd_ = -1;
  std::vector<MappedBuffer> buffers_;
  uint32_t pixelformat_ = 0;
  int bytesperline_ = 0;
  std::string camera_id_;
  int width_ = 1280;
  int height_ = 720;
  int frame_rate_ = 30;
  int request_width_ = 1280;
  int request_height_ = 720;
  int request_frame_rate_ = 30;
};

#endif  // FLUTTER_PLUGIN_LINUX_CAMERA_GRAPH_H_
