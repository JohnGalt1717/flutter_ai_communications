#include "camera_graph.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/dma-buf.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <gtk/gtk.h>

#include <algorithm>
#include <climits>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

#ifdef FAC_HAS_PIPEWIRE
#include <pipewire/loop.h>
#include <pipewire/pipewire.h>
#include <spa/param/buffers.h>
#include <spa/param/format.h>
#include <spa/param/video/format-utils.h>
#include <spa/param/video/raw.h>
#include <spa/pod/builder.h>
#include <spa/pod/iter.h>
#endif

namespace {

std::string ToLower(std::string value) {
  for (char& ch : value) {
    if (ch >= 'A' && ch <= 'Z') {
      ch = static_cast<char>(ch - 'A' + 'a');
    }
  }
  return value;
}

bool Contains(const std::string& haystack, const char* needle) {
  return haystack.find(needle) != std::string::npos;
}

bool IsCaptureDevice(int fd) {
  v4l2_capability cap = {};
  if (ioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
    return false;
  }
  const uint32_t caps =
      cap.device_caps != 0 ? cap.device_caps : cap.capabilities;
  return (caps & V4L2_CAP_VIDEO_CAPTURE) != 0 &&
         (caps & V4L2_CAP_STREAMING) != 0;
}

bool CanConvert(uint32_t fourcc) {
  return fourcc == V4L2_PIX_FMT_YUYV || fourcc == V4L2_PIX_FMT_NV12 ||
         fourcc == V4L2_PIX_FMT_RGB24 || fourcc == V4L2_PIX_FMT_BGR24 ||
         fourcc == V4L2_PIX_FMT_MJPEG || fourcc == V4L2_PIX_FMT_JPEG;
}

void FacCameraLog(const char* fmt, ...) G_GNUC_PRINTF(1, 2);
void FacCameraLog(const char* fmt, ...) {
  FILE* file = fopen("/tmp/fac-camera.log", "a");
  if (file == nullptr) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  vfprintf(file, fmt, args);
  va_end(args);
  fputc('\n', file);
  fclose(file);
}

bool LooksLiveRgba(const uint8_t* pixels, size_t bytes) {
  if (pixels == nullptr || bytes < 4) {
    return false;
  }
  int samples = 0;
  int any = 0;
  int chroma_zero = 0;
  for (size_t i = 0; i + 3 < bytes; i += 64) {
    samples++;
    const int r = pixels[i];
    const int g = pixels[i + 1];
    const int b = pixels[i + 2];
    if (g > 24 && r < 10 && b < 10) {
      chroma_zero++;
    } else if (r > 8 || g > 8 || b > 8) {
      any++;
    }
  }
  return samples > 0 && chroma_zero * 2 < samples && any > 0;
}

bool DecodeJpegRgba(const uint8_t* src, size_t length, int width, int height,
                    uint8_t* dst) {
  if (src == nullptr || dst == nullptr || length < 4 || width < 1 ||
      height < 1) {
    return false;
  }
  g_autoptr(GMemoryInputStream) stream = G_MEMORY_INPUT_STREAM(
      g_memory_input_stream_new_from_data(src, length, nullptr));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_stream_at_scale(
      G_INPUT_STREAM(stream), width, height, FALSE, nullptr, &error);
  if (pixbuf == nullptr) {
    return false;
  }
  const int src_w = gdk_pixbuf_get_width(pixbuf);
  const int src_h = gdk_pixbuf_get_height(pixbuf);
  const int channels = gdk_pixbuf_get_n_channels(pixbuf);
  const int stride = gdk_pixbuf_get_rowstride(pixbuf);
  const uint8_t* pixels = gdk_pixbuf_get_pixels(pixbuf);
  if (pixels == nullptr || channels < 3 || src_w < 1 || src_h < 1) {
    return false;
  }
  for (int y = 0; y < height; y++) {
    const int src_y = y * src_h / height;
    const uint8_t* row = pixels + static_cast<ptrdiff_t>(stride) * src_y;
    uint8_t* out = dst + static_cast<size_t>(y) * width * 4;
    for (int x = 0; x < width; x++) {
      const int src_x = x * src_w / width;
      const uint8_t* px = row + src_x * channels;
      out[x * 4 + 0] = px[0];
      out[x * 4 + 1] = px[1];
      out[x * 4 + 2] = px[2];
      out[x * 4 + 3] = 255;
    }
  }
  return true;
}

uint8_t Clamp(int value) {
  if (value < 0) {
    return 0;
  }
  if (value > 255) {
    return 255;
  }
  return static_cast<uint8_t>(value);
}

}  // namespace

struct CameraGraph::PwCapture {
#ifdef FAC_HAS_PIPEWIRE
  pw_thread_loop* loop = nullptr;
  pw_context* context = nullptr;
  pw_core* core = nullptr;
  pw_registry* registry = nullptr;
  spa_hook registry_listener{};
  pw_registry_events registry_events{};
  pw_stream* stream = nullptr;
  spa_hook listener{};
  pw_stream_events events{};
  uint32_t spa_format = 0;
  int src_w = 0;
  int src_h = 0;
  int process_logs = 0;
  uint32_t node_id = PW_ID_ANY;
  std::string path;
  std::string node_name;
  std::atomic<bool> failed{false};
  std::atomic<bool> activated{false};
  spa_source* timer = nullptr;
#endif
};

G_DECLARE_FINAL_TYPE(FacPixelTexture,
                     fac_pixel_texture,
                     FAC,
                     PIXEL_TEXTURE,
                     FlPixelBufferTexture)

struct _FacPixelTexture {
  FlPixelBufferTexture parent_instance;
  CameraGraph* graph;
};

G_DEFINE_TYPE(FacPixelTexture,
              fac_pixel_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean fac_pixel_texture_copy_pixels(FlPixelBufferTexture* texture,
                                              const uint8_t** buffer,
                                              uint32_t* width,
                                              uint32_t* height,
                                              GError** error) {
  FacPixelTexture* self = FAC_PIXEL_TEXTURE(texture);
  if (self->graph == nullptr) {
    return FALSE;
  }
  return self->graph->CopyPixels(buffer, width, height, error);
}

static void fac_pixel_texture_class_init(FacPixelTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      fac_pixel_texture_copy_pixels;
}

static void fac_pixel_texture_init(FacPixelTexture* self) {
  self->graph = nullptr;
}

CameraGraph::CameraGraph(FlTextureRegistrar* textures, GtkWidget* view)
    : textures_(textures), view_(view) {
  (void)view_;
}

CameraGraph::~CameraGraph() {
  Stop();
  if (textures_ != nullptr && texture_ != nullptr) {
    fl_texture_registrar_unregister_texture(textures_, FL_TEXTURE(texture_));
  }
  if (texture_ != nullptr) {
    g_object_unref(texture_);
    texture_ = nullptr;
  }
}

void CameraGraph::EnsureTexture() {
  if (texture_ != nullptr || textures_ == nullptr) {
    return;
  }
  auto* pixel = FAC_PIXEL_TEXTURE(
      g_object_new(fac_pixel_texture_get_type(), nullptr));
  pixel->graph = this;
  texture_ = FL_PIXEL_BUFFER_TEXTURE(pixel);
  if (!fl_texture_registrar_register_texture(textures_, FL_TEXTURE(texture_))) {
    g_object_unref(texture_);
    texture_ = nullptr;
    return;
  }
  texture_id_ = fl_texture_get_id(FL_TEXTURE(texture_));
}

std::string CameraGraph::FacingFor(const std::string& name,
                                   const std::string& bus_info) {
  const std::string haystack = ToLower(name + " " + bus_info);
  if (Contains(haystack, "front") || Contains(haystack, "user") ||
      Contains(haystack, "integrated") || Contains(haystack, "internal")) {
    return "user";
  }
  if (Contains(haystack, "rear") || Contains(haystack, "back")) {
    return "environment";
  }
  if (Contains(haystack, "usb")) {
    return "external";
  }
  return "unspecified";
}

FlValue* CameraGraph::Enumerate() {
  FlValue* cameras = fl_value_new_list();
  for (int i = 0; i < 64; i++) {
    const std::string path = "/dev/video" + std::to_string(i);
    int fd = open(path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd < 0) {
      fd = open(path.c_str(), O_RDONLY | O_NONBLOCK);
    }
    if (fd < 0) {
      continue;
    }
    if (!IsCaptureDevice(fd)) {
      close(fd);
      continue;
    }
    v4l2_capability cap = {};
    ioctl(fd, VIDIOC_QUERYCAP, &cap);
    close(fd);
    const std::string name = reinterpret_cast<const char*>(cap.card);
    const std::string bus = reinterpret_cast<const char*>(cap.bus_info);
    FacCameraLog("enumerate %s name=%s bus=%s", path.c_str(), name.c_str(),
                 bus.c_str());
    FlValue* camera = fl_value_new_map();
    fl_value_set_string_take(camera, "id", fl_value_new_string(path.c_str()));
    fl_value_set_string_take(camera, "name",
                             fl_value_new_string(name.c_str()));
    fl_value_set_string_take(camera, "facing",
                             fl_value_new_string(FacingFor(name, bus).c_str()));
    FlValue* mode = fl_value_new_map();
    fl_value_set_string_take(mode, "width", fl_value_new_int(1280));
    fl_value_set_string_take(mode, "height", fl_value_new_int(720));
    fl_value_set_string_take(mode, "frameRate", fl_value_new_int(30));
    FlValue* modes = fl_value_new_list();
    fl_value_append_take(modes, mode);
    fl_value_set_string_take(camera, "modes", modes);
    fl_value_append_take(cameras, camera);
  }
  FacCameraLog("enumerate count=%zu", fl_value_get_length(cameras));
  return cameras;
}

std::string CameraGraph::RequestPermission() {
  bool saw_capture = false;
  bool denied = false;
  for (int i = 0; i < 64; i++) {
    const std::string path = "/dev/video" + std::to_string(i);
    const int fd = open(path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd < 0) {
      if (errno == EACCES || errno == EPERM) {
        denied = true;
      }
      continue;
    }
    if (!IsCaptureDevice(fd)) {
      close(fd);
      continue;
    }
    saw_capture = true;
    close(fd);
  }
  if (saw_capture) {
    FacCameraLog("permission granted via v4l2");
    return "granted";
  }
  if (AccessCameraPortal()) {
    FacCameraLog("permission granted via portal");
    return "granted";
  }
  FacCameraLog("permission denied saw_capture=0 denied=%d", denied ? 1 : 0);
  return denied ? "denied" : "denied";
}

FlValue* CameraGraph::Start(const std::string& camera_id,
                            int width,
                            int height,
                            int frame_rate,
                            bool enabled,
                            bool muted) {
  EnsureTexture();
  FlValue* result = fl_value_new_map();
  if (texture_id_ < 0) {
    fl_value_set_string_take(result, "status", fl_value_new_string("failed"));
    return result;
  }
  request_width_ = width > 0 ? width : 1280;
  request_height_ = height > 0 ? height : 720;
  request_frame_rate_ = frame_rate > 0 ? frame_rate : 30;
  width_ = request_width_;
  height_ = request_height_;
  frame_rate_ = request_frame_rate_;
  enabled_.store(enabled);
  muted_.store(muted);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    FillBlackLocked();
  }
  if (!enabled) {
    StopCapture();
    frame_count_.store(0);
    live_frames_.store(0);
    if (textures_ != nullptr && texture_ != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(textures_,
                                                        FL_TEXTURE(texture_));
    }
    fl_value_set_string_take(result, "status", fl_value_new_string("started"));
    fl_value_set_string_take(result, "textureId",
                             fl_value_new_int(texture_id_));
    fl_value_set_string_take(result, "width", fl_value_new_int(width_));
    fl_value_set_string_take(result, "height", fl_value_new_int(height_));
    fl_value_set_string_take(result, "frameRate",
                             fl_value_new_int(frame_rate_));
    return result;
  }
  if (!StartCapture(camera_id, request_width_, request_height_,
                    request_frame_rate_)) {
    fl_value_set_string_take(result, "status",
                             fl_value_new_string("unavailable"));
    return result;
  }
  fl_value_set_string_take(result, "status", fl_value_new_string("started"));
  fl_value_set_string_take(result, "textureId", fl_value_new_int(texture_id_));
  fl_value_set_string_take(result, "width", fl_value_new_int(width_));
  fl_value_set_string_take(result, "height", fl_value_new_int(height_));
  fl_value_set_string_take(result, "frameRate", fl_value_new_int(frame_rate_));
  return result;
}

void CameraGraph::Stop() { StopCapture(); }

std::string CameraGraph::SetProcessor(FlValue* args) {
  return processor_.Apply(args);
}

void CameraGraph::Select(const std::string& camera_id) {
  FlValue* result =
      Start(camera_id, request_width_, request_height_, request_frame_rate_,
            enabled_.load(), muted_.load());
  fl_value_unref(result);
}

void CameraGraph::SetEnabled(bool enabled) {
  enabled_.store(enabled);
  if (!enabled) {
    StopCapture();
    std::lock_guard<std::mutex> lock(mutex_);
    FillBlackLocked();
    if (textures_ != nullptr && texture_ != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(textures_,
                                                        FL_TEXTURE(texture_));
    }
    return;
  }
  StartCapture(camera_id_, request_width_, request_height_,
               request_frame_rate_);
}

FlValue* CameraGraph::Stats() const {
  FlValue* stats = fl_value_new_map();
  fl_value_set_string_take(stats, "frameCount",
                           fl_value_new_int(frame_count_.load()));
  fl_value_set_string_take(stats, "liveFrames",
                           fl_value_new_int(live_frames_.load()));
  return stats;
}

void CameraGraph::SetMuted(bool muted) {
  muted_.store(muted);
  if (muted) {
    std::lock_guard<std::mutex> lock(mutex_);
    FillBlackLocked();
  }
  if (textures_ != nullptr && texture_ != nullptr) {
    fl_texture_registrar_mark_texture_frame_available(textures_,
                                                      FL_TEXTURE(texture_));
  }
}

void CameraGraph::StopCapture() {
  running_.store(false);
  StopPipeWire();
  if (fd_ >= 0) {
    v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    ioctl(fd_, VIDIOC_STREAMOFF, &type);
  }
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  for (auto& buffer : buffers_) {
    if (buffer.start != nullptr && buffer.start != MAP_FAILED) {
      munmap(buffer.start, buffer.length);
    }
  }
  buffers_.clear();
  if (fd_ >= 0) {
    close(fd_);
    fd_ = -1;
  }
}

bool CameraGraph::ProbeLiveFrames() {
  live_frames_.store(0);
  for (int i = 0; i < 16; i++) {
    pollfd pfd = {};
    pfd.fd = fd_;
    pfd.events = POLLIN;
    if (poll(&pfd, 1, 50) <= 0) {
      continue;
    }
    v4l2_buffer buf = {};
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    if (ioctl(fd_, VIDIOC_DQBUF, &buf) < 0) {
      continue;
    }
    if (buf.index < buffers_.size()) {
      ConvertFrame(static_cast<const uint8_t*>(buffers_[buf.index].start),
                   buf.bytesused);
    }
    ioctl(fd_, VIDIOC_QBUF, &buf);
    if (live_frames_.load() > 0) {
      return true;
    }
  }
  return false;
}

bool CameraGraph::StartCapture(const std::string& camera_id,
                               int width,
                               int height,
                               int frame_rate) {
  FacCameraLog("StartCapture id=%s %dx%d@%d", camera_id.c_str(), width, height,
               frame_rate);
  StopCapture();
  std::vector<std::string> paths;
  if (!camera_id.empty()) {
    paths.push_back(camera_id);
  } else {
    FlValue* cameras = Enumerate();
    for (size_t i = 0; i < fl_value_get_length(cameras); i++) {
      FlValue* camera = fl_value_get_list_value(cameras, i);
      FlValue* id = camera != nullptr ? fl_value_lookup_string(camera, "id")
                                      : nullptr;
      if (id == nullptr) {
        continue;
      }
      const std::string path = fl_value_get_string(id);
      if (!path.empty()) {
        paths.push_back(path);
      }
    }
    fl_value_unref(cameras);
  }
  if (paths.empty()) {
    return false;
  }

  auto release_buffers = [this]() {
    if (fd_ >= 0) {
      v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
      ioctl(fd_, VIDIOC_STREAMOFF, &type);
    }
    for (auto& buffer : buffers_) {
      if (buffer.start != nullptr && buffer.start != MAP_FAILED) {
        munmap(buffer.start, buffer.length);
      }
    }
    buffers_.clear();
    if (fd_ >= 0) {
      v4l2_requestbuffers req = {};
      req.count = 0;
      req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
      req.memory = V4L2_MEMORY_MMAP;
      ioctl(fd_, VIDIOC_REQBUFS, &req);
    }
  };

  auto close_device = [this, &release_buffers]() {
    release_buffers();
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
  };

  auto open_device = [this, &close_device](const std::string& path) -> bool {
    close_device();
    fd_ = open(path.c_str(), O_RDWR);
    if (fd_ < 0 || !IsCaptureDevice(fd_)) {
      const int err = errno;
      if (fd_ >= 0) {
        close(fd_);
        fd_ = -1;
      }
      FacCameraLog("open failed %s errno=%d", path.c_str(), err);
      return false;
    }
    return true;
  };

  // MJPEG 640x480 first: USB 2 passthrough cannot carry uncompressed YUYV
  // together with the BRIO's USB audio interface (STREAMON EPIPE).
  const uint32_t candidates[] = {
      V4L2_PIX_FMT_MJPEG, V4L2_PIX_FMT_JPEG, V4L2_PIX_FMT_YUYV,
      V4L2_PIX_FMT_NV12, V4L2_PIX_FMT_RGB24, V4L2_PIX_FMT_BGR24};
  const int sizes[][2] = {{640, 480}, {width, height}, {1280, 720}, {0, 0}};

  for (const auto& path : paths) {
    if (StartPipeWire(path)) {
      FacCameraLog("pipewire capture %s", path.c_str());
      return true;
    }
  }
  if (std::getenv("FAC_ALLOW_V4L2") == nullptr) {
    FacCameraLog("StartCapture skip v4l2 after pipewire");
    return false;
  }

  bool opened_v4l2 = false;
  for (const auto& path : paths) {
    if (!open_device(path)) {
      continue;
    }
    opened_v4l2 = true;
    camera_id_ = path;
    bool started = false;
    for (uint32_t fourcc : candidates) {
      for (const auto& size : sizes) {
        if (fd_ < 0 && !open_device(path)) {
          break;
        }
        v4l2_format fmt = {};
        if (!TrySetFormat(fourcc, size[0], size[1], &fmt) ||
            !CanConvert(fmt.fmt.pix.pixelformat)) {
          continue;
        }
        pixelformat_ = fmt.fmt.pix.pixelformat;
        width_ = static_cast<int>(fmt.fmt.pix.width);
        height_ = static_cast<int>(fmt.fmt.pix.height);
        bytesperline_ = static_cast<int>(fmt.fmt.pix.bytesperline);
        frame_rate_ = frame_rate;
        v4l2_requestbuffers req = {};
        req.count = 4;
        req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        req.memory = V4L2_MEMORY_MMAP;
        if (ioctl(fd_, VIDIOC_REQBUFS, &req) < 0 || req.count < 2) {
          FacCameraLog("REQBUFS failed %s fourcc=%u %dx%d errno=%d",
                       path.c_str(), fourcc, width_, height_, errno);
          release_buffers();
          continue;
        }
        buffers_.resize(req.count);
        bool mapped = true;
        for (uint32_t i = 0; i < req.count; i++) {
          v4l2_buffer buf = {};
          buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
          buf.memory = V4L2_MEMORY_MMAP;
          buf.index = i;
          if (ioctl(fd_, VIDIOC_QUERYBUF, &buf) < 0) {
            mapped = false;
            break;
          }
          buffers_[i].length = buf.length;
          buffers_[i].start =
              mmap(nullptr, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd_,
                   buf.m.offset);
          if (buffers_[i].start == MAP_FAILED) {
            mapped = false;
            break;
          }
          if (ioctl(fd_, VIDIOC_QBUF, &buf) < 0) {
            mapped = false;
            break;
          }
        }
        if (!mapped) {
          FacCameraLog("mmap/qbuf failed %s fourcc=%u %dx%d", path.c_str(),
                       fourcc, width_, height_);
          release_buffers();
          continue;
        }
        v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        FacCameraLog("STREAMON try %s fourcc=%u %dx%d", path.c_str(),
                     pixelformat_, width_, height_);
        if (ioctl(fd_, VIDIOC_STREAMON, &type) < 0) {
          FacCameraLog("STREAMON failed %s fourcc=%u %dx%d errno=%d",
                       path.c_str(), pixelformat_, width_, height_, errno);
          close_device();
          usleep(200000);
          if (!open_device(path)) {
            break;
          }
          continue;
        }
        {
          std::lock_guard<std::mutex> lock(mutex_);
          FillBlackLocked();
        }
        frame_count_.store(0);
        const bool live = ProbeLiveFrames();
        FacCameraLog("probe %s fourcc=%c%c%c%c %dx%d live=%d frames=%ld",
                     path.c_str(), static_cast<char>(pixelformat_ & 0xff),
                     static_cast<char>((pixelformat_ >> 8) & 0xff),
                     static_cast<char>((pixelformat_ >> 16) & 0xff),
                     static_cast<char>((pixelformat_ >> 24) & 0xff), width_,
                     height_, live ? 1 : 0,
                     static_cast<long>(live_frames_.load()));
        if (!live) {
          close_device();
          usleep(20000);
          if (!open_device(path)) {
            break;
          }
          continue;
        }
        running_.store(true);
        capture_thread_ = std::thread([this]() { CaptureLoop(); });
        started = true;
        break;
      }
      if (started) {
        break;
      }
    }
    if (started) {
      return true;
    }
    close_device();
  }
  (void)opened_v4l2;
  FacCameraLog("StartCapture no live camera");
  return false;
}

void CameraGraph::StopPipeWire() {
#ifdef FAC_HAS_PIPEWIRE
  StopPwPoll();
  if (!pw_) {
    return;
  }
  if (pw_->loop != nullptr) {
    pw_thread_loop_lock(pw_->loop);
    if (pw_->timer != nullptr) {
      pw_loop_destroy_source(pw_thread_loop_get_loop(pw_->loop), pw_->timer);
      pw_->timer = nullptr;
    }
    if (pw_->stream != nullptr) {
      spa_hook_remove(&pw_->listener);
      pw_stream_disconnect(pw_->stream);
      pw_stream_destroy(pw_->stream);
      pw_->stream = nullptr;
    }
    if (pw_->registry != nullptr) {
      spa_hook_remove(&pw_->registry_listener);
      pw_->registry = nullptr;
    }
    if (pw_->core != nullptr) {
      pw_core_disconnect(pw_->core);
      pw_->core = nullptr;
    }
    if (pw_->context != nullptr) {
      pw_context_destroy(pw_->context);
      pw_->context = nullptr;
    }
    pw_thread_loop_unlock(pw_->loop);
    pw_thread_loop_stop(pw_->loop);
    pw_thread_loop_destroy(pw_->loop);
    pw_->loop = nullptr;
  }
  pw_.reset();
#endif
}

bool CameraGraph::AccessCameraPortal() {
  if (portal_granted_) {
    return true;
  }
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusProxy) proxy = g_dbus_proxy_new_for_bus_sync(
      G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, nullptr,
      "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.Camera", nullptr, &error);
  if (proxy == nullptr) {
    FacCameraLog("camera portal missing %s",
                 error != nullptr ? error->message : "");
    return false;
  }
  GDBusConnection* bus = g_dbus_proxy_get_connection(proxy);
  const gchar* unique =
      bus != nullptr ? g_dbus_connection_get_unique_name(bus) : nullptr;
  if (unique == nullptr || unique[0] != ':') {
    return false;
  }
  char token[32];
  g_snprintf(token, sizeof(token), "fac%d", g_random_int_range(1, G_MAXINT));
  std::string sender(unique + 1);
  for (char& c : sender) {
    if (c == '.') {
      c = '_';
    }
  }
  const std::string request_path =
      std::string("/org/freedesktop/portal/desktop/request/") + sender + "/" +
      token;
  struct Wait {
    GMainLoop* loop = nullptr;
    guint code = 2;
    bool done = false;
  } wait;
  wait.loop = g_main_loop_new(g_main_context_default(), FALSE);
  const guint sub = g_dbus_connection_signal_subscribe(
      bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
      "Response", request_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      [](GDBusConnection*, const gchar*, const gchar*, const gchar*,
         const gchar*, GVariant* parameters, gpointer user_data) {
        auto* wait = static_cast<Wait*>(user_data);
        GVariant* results = nullptr;
        g_variant_get(parameters, "(u@a{sv})", &wait->code, &results);
        if (results != nullptr) {
          g_variant_unref(results);
        }
        wait->done = true;
        if (wait->loop != nullptr) {
          g_main_loop_quit(wait->loop);
        }
      },
      &wait, nullptr);
  GVariantBuilder opts;
  g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&opts, "{sv}", "handle_token",
                        g_variant_new_string(token));
  g_autoptr(GError) call_error = nullptr;
  g_autoptr(GVariant) ret = g_dbus_proxy_call_sync(
      proxy, "AccessCamera", g_variant_new("(a{sv})", &opts),
      G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &call_error);
  FacCameraLog("AccessCamera ret=%p err=%s path=%s",
               static_cast<const void*>(ret),
               call_error != nullptr ? call_error->message : "none",
               request_path.c_str());
  if (ret == nullptr && !wait.done) {
    g_dbus_connection_signal_unsubscribe(bus, sub);
    g_main_loop_unref(wait.loop);
    return false;
  }
  if (!wait.done) {
    const guint timeout_id = g_timeout_add(
        120000,
        [](gpointer data) -> gboolean {
          auto* wait = static_cast<Wait*>(data);
          if (wait->loop != nullptr) {
            g_main_loop_quit(wait->loop);
          }
          return G_SOURCE_REMOVE;
        },
        &wait);
    g_main_loop_run(wait.loop);
    g_source_remove(timeout_id);
  }
  g_dbus_connection_signal_unsubscribe(bus, sub);
  g_main_loop_unref(wait.loop);
  FacCameraLog("AccessCamera response=%u", wait.code);
  portal_granted_ = wait.code == 0;
  return portal_granted_;
}

int CameraGraph::OpenCameraPipeWireRemote() {
  if (!portal_granted_ && !AccessCameraPortal()) {
    return -1;
  }
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusProxy) proxy = g_dbus_proxy_new_for_bus_sync(
      G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, nullptr,
      "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.Camera", nullptr, &error);
  if (proxy == nullptr) {
    return -1;
  }
  g_autoptr(GUnixFDList) fd_list = nullptr;
  GVariantBuilder opts;
  g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
  g_autoptr(GVariant) ret = g_dbus_proxy_call_with_unix_fd_list_sync(
      proxy, "OpenPipeWireRemote", g_variant_new("(a{sv})", &opts),
      G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &fd_list, nullptr, &error);
  if (ret == nullptr || fd_list == nullptr) {
    FacCameraLog("OpenPipeWireRemote camera err=%s",
                 error != nullptr ? error->message : "none");
    return -1;
  }
  gint32 handle = -1;
  g_variant_get(ret, "(h)", &handle);
  int fd = g_unix_fd_list_get(fd_list, handle, &error);
  FacCameraLog("OpenPipeWireRemote camera fd=%d", fd);
  return fd;
}

bool CameraGraph::StartPipeWire(const std::string& camera_id) {
#ifdef FAC_HAS_PIPEWIRE
  if (camera_id.empty()) {
    return false;
  }
  StopPipeWire();
  static std::once_flag pw_once;
  std::call_once(pw_once, [] { pw_init(nullptr, nullptr); });
  pw_ = std::make_unique<PwCapture>();
  pw_->path = camera_id.rfind("/dev/", 0) == 0 ? std::string("v4l2:") + camera_id
                                               : camera_id;
  pw_->loop = pw_thread_loop_new("fac-camera", nullptr);
  if (pw_->loop == nullptr) {
    pw_.reset();
    return false;
  }
  if (pw_thread_loop_start(pw_->loop) < 0) {
    StopPipeWire();
    return false;
  }
  pw_thread_loop_lock(pw_->loop);
  pw_->context = pw_context_new(pw_thread_loop_get_loop(pw_->loop), nullptr, 0);
  if (pw_->context == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    return false;
  }
  // Default PipeWire socket so WirePlumber owns V4L2 STREAMON and can share
  // the BRIO with USB audio. The Camera portal remote is not used here.
  pw_->core = pw_context_connect(pw_->context, nullptr, 0);
  if (pw_->core == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    return false;
  }
  pw_->registry = pw_core_get_registry(pw_->core, PW_VERSION_REGISTRY, 0);
  if (pw_->registry == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    return false;
  }
  pw_->registry_events = {};
  pw_->registry_events.version = PW_VERSION_REGISTRY_EVENTS;
  pw_->registry_events.global = [](void* data, uint32_t id,
                                   uint32_t /*permissions*/, const char* type,
                                   uint32_t /*version*/,
                                   const spa_dict* props) {
    auto* self = static_cast<CameraGraph*>(data);
    if (self == nullptr || self->pw_ == nullptr || type == nullptr ||
        props == nullptr || std::strcmp(type, PW_TYPE_INTERFACE_Node) != 0) {
      return;
    }
    const char* klass = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    const char* path = spa_dict_lookup(props, PW_KEY_OBJECT_PATH);
    if (klass == nullptr || std::strstr(klass, "Video/Source") == nullptr) {
      return;
    }
    const bool path_match =
        path != nullptr && self->pw_->path == path;
    const bool id_match =
        path != nullptr && self->pw_->path.find(path) != std::string::npos;
    if (!path_match && !id_match) {
      return;
    }
    self->pw_->node_id = id;
    const char* name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
    if (name != nullptr) {
      self->pw_->node_name = name;
    }
    FacCameraLog("pw camera node=%u path=%s name=%s", id,
                 path != nullptr ? path : "", name != nullptr ? name : "");
  };
  pw_registry_add_listener(pw_->registry, &pw_->registry_listener,
                           &pw_->registry_events, this);
  pw_thread_loop_unlock(pw_->loop);
  for (int i = 0; i < 40 && pw_->node_id == PW_ID_ANY; i++) {
    g_usleep(25000);
  }
  if (pw_->registry != nullptr) {
    pw_thread_loop_lock(pw_->loop);
    spa_hook_remove(&pw_->registry_listener);
    pw_->registry = nullptr;
    pw_thread_loop_unlock(pw_->loop);
  }
  if (pw_->node_id == PW_ID_ANY) {
    FacCameraLog("pw camera node not found for %s", pw_->path.c_str());
    StopPipeWire();
    return false;
  }
  pw_thread_loop_lock(pw_->loop);
  // object.path (v4l2:/dev/video0) is unique. node.name prefixes the IR
  // node (...usb-0_1_1.0.2) and WirePlumber would bind GRAY 340x340.
  const char* target = pw_->path.c_str();
  pw_properties* props = pw_properties_new(
      PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY, "Capture",
      PW_KEY_MEDIA_CLASS, "Stream/Input/Video", PW_KEY_TARGET_OBJECT, target,
      nullptr);
  pw_->stream = pw_stream_new(pw_->core, "fac-camera", props);
  if (pw_->stream == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    return false;
  }
  pw_->events.version = PW_VERSION_STREAM_EVENTS;
  pw_->events.param_changed = [](void* data, uint32_t id,
                                 const spa_pod* param) {
    CameraGraph::OnPwParamChanged(data, id, param);
  };
  pw_->events.add_buffer = [](void* data, pw_buffer* /*buffer*/) {
    auto* self = static_cast<CameraGraph*>(data);
    FacCameraLog("pw camera add_buffer");
    if (self != nullptr && self->pw_ != nullptr && self->pw_->loop != nullptr) {
      pw_thread_loop_signal(self->pw_->loop, false);
    }
  };
  pw_->events.process = [](void* data) { CameraGraph::OnPwProcess(data); };
  pw_->events.state_changed = [](void* data, pw_stream_state /*old*/,
                                 pw_stream_state next, const char* error) {
    auto* self = static_cast<CameraGraph*>(data);
    FacCameraLog("pw camera state=%s error=%s", pw_stream_state_as_string(next),
                 error != nullptr ? error : "");
    if (self == nullptr || self->pw_ == nullptr) {
      return;
    }
    if (next == PW_STREAM_STATE_ERROR) {
      self->pw_->failed.store(true);
    }
    if (self->pw_->loop != nullptr) {
      pw_thread_loop_signal(self->pw_->loop, false);
    }
  };
  pw_stream_add_listener(pw_->stream, &pw_->listener, &pw_->events, this);
  // Match gst pipewiresrc: no MAP_BUFFERS. Modifier formats need DMA-BUF
  // only; MAP_BUFFERS makes v4l2 "use input buffers" fail with -22.
  const int connected = pw_stream_connect(
      pw_->stream, PW_DIRECTION_INPUT, PW_ID_ANY,
      static_cast<pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT |
                                   PW_STREAM_FLAG_DONT_RECONNECT |
                                   PW_STREAM_FLAG_ASYNC),
      nullptr, 0);
  FacCameraLog("pw camera connect rc=%d node=%u target=%s %s", connected,
               pw_->node_id, target, camera_id.c_str());
  pw_thread_loop_unlock(pw_->loop);
  if (connected < 0) {
    StopPipeWire();
    return false;
  }
  for (int i = 0; i < 80 && live_frames_.load() == 0 && !pw_->failed.load();
       i++) {
    g_usleep(50000);
  }
  if (pw_->failed.load() || pw_->spa_format == 0) {
    FacCameraLog("pw camera not live format=%u", pw_->spa_format);
    StopPipeWire();
    return false;
  }
  FacCameraLog("pw camera live format=%u %dx%d frames=%ld", pw_->spa_format,
               pw_->src_w, pw_->src_h, static_cast<long>(live_frames_.load()));
  if (live_frames_.load() == 0) {
    FacCameraLog("pw camera no live frames; falling back");
    StopPipeWire();
    return false;
  }
  camera_id_ = camera_id;
  running_.store(true);
  return true;
#else
  (void)camera_id;
  return false;
#endif
}

void CameraGraph::StartPwPoll() {
  if (pw_poll_id_ != 0) {
    return;
  }
  pw_poll_id_ = g_timeout_add(
      16,
      [](gpointer user) -> gboolean {
        auto* self = static_cast<CameraGraph*>(user);
        if (!self->running_.load() || self->pw_ == nullptr ||
            self->pw_->stream == nullptr || self->pw_->loop == nullptr) {
          self->pw_poll_id_ = 0;
          return G_SOURCE_REMOVE;
        }
        pw_thread_loop_lock(self->pw_->loop);
        CameraGraph::OnPwProcess(self);
        pw_thread_loop_unlock(self->pw_->loop);
        return G_SOURCE_CONTINUE;
      },
      this);
}

void CameraGraph::StopPwPoll() {
  if (pw_poll_id_ == 0) {
    return;
  }
  g_source_remove(pw_poll_id_);
  pw_poll_id_ = 0;
}

void CameraGraph::OnPwParamChanged(void* data, uint32_t id, const void* param) {
#ifdef FAC_HAS_PIPEWIRE
  auto* self = static_cast<CameraGraph*>(data);
  if (self == nullptr || self->pw_ == nullptr || param == nullptr ||
      id != SPA_PARAM_Format) {
    return;
  }
  spa_video_info_raw raw{};
  if (spa_format_video_raw_parse(static_cast<const spa_pod*>(param), &raw) <
      0) {
    return;
  }
  self->pw_->spa_format = raw.format;
  self->pw_->src_w = static_cast<int>(raw.size.width);
  self->pw_->src_h = static_cast<int>(raw.size.height);
  if (self->pw_->src_w > 0) {
    self->width_ = self->pw_->src_w;
  }
  if (self->pw_->src_h > 0) {
    self->height_ = self->pw_->src_h;
  }
  if (raw.format == SPA_VIDEO_FORMAT_YUY2) {
    self->pixelformat_ = V4L2_PIX_FMT_YUYV;
  } else if (raw.format == SPA_VIDEO_FORMAT_NV12) {
    self->pixelformat_ = V4L2_PIX_FMT_NV12;
  } else if (raw.format == SPA_VIDEO_FORMAT_RGB) {
    self->pixelformat_ = V4L2_PIX_FMT_RGB24;
  } else if (raw.format == SPA_VIDEO_FORMAT_BGR) {
    self->pixelformat_ = V4L2_PIX_FMT_BGR24;
  } else if (raw.format == SPA_VIDEO_FORMAT_GRAY8) {
    self->pixelformat_ = V4L2_PIX_FMT_GREY;
  } else {
    self->pixelformat_ = 0;
  }
  FacCameraLog("pw camera format=%u %dx%d modifier=%llu flags=%u", raw.format,
               self->pw_->src_w, self->pw_->src_h,
               static_cast<unsigned long long>(raw.modifier), raw.flags);
  if (self->pw_->stream == nullptr || self->pw_->src_w < 1 ||
      self->pw_->src_h < 1) {
    return;
  }
  const int stride =
      self->pw_->src_w *
      (raw.format == SPA_VIDEO_FORMAT_NV12
           ? 1
           : (raw.format == SPA_VIDEO_FORMAT_RGB ||
                      raw.format == SPA_VIDEO_FORMAT_BGR
                  ? 3
                  : 2));
  const int size = stride * self->pw_->src_h;
  uint32_t data_type = (1u << SPA_DATA_DmaBuf);
  if (spa_pod_find_prop(static_cast<const spa_pod*>(param), nullptr,
                        SPA_FORMAT_VIDEO_modifier) == nullptr) {
    data_type |= (1u << SPA_DATA_MemFd) | (1u << SPA_DATA_MemPtr);
  }
  uint8_t pod_buf[512];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(pod_buf, sizeof(pod_buf));
  spa_pod* buffers_pod = static_cast<spa_pod*>(spa_pod_builder_add_object(
      &builder, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
      SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(8, 2, 16),
      SPA_PARAM_BUFFERS_blocks, SPA_POD_CHOICE_RANGE_Int(0, 1, 16),
      SPA_PARAM_BUFFERS_size, SPA_POD_CHOICE_RANGE_Int(size, 1, INT32_MAX),
      SPA_PARAM_BUFFERS_stride, SPA_POD_CHOICE_RANGE_Int(stride, 0, INT32_MAX),
      SPA_PARAM_BUFFERS_dataType, SPA_POD_CHOICE_FLAGS_Int(data_type)));
  if (buffers_pod != nullptr) {
    const spa_pod* params[1] = {buffers_pod};
    const int updated = pw_stream_update_params(self->pw_->stream, params, 1);
    FacCameraLog("pw camera buffers update rc=%d type=%u size=%d stride=%d",
                 updated, data_type, size, stride);
  }
  if (self->pw_->loop != nullptr) {
    pw_thread_loop_signal(self->pw_->loop, false);
  }
#else
  (void)data;
  (void)id;
  (void)param;
#endif
}

void CameraGraph::OnPwProcess(void* data) {
#ifdef FAC_HAS_PIPEWIRE
  auto* self = static_cast<CameraGraph*>(data);
  if (self != nullptr && self->pw_ != nullptr && self->pw_->loop != nullptr) {
    pw_thread_loop_signal(self->pw_->loop, false);
  }
  if (self == nullptr || self->pw_ == nullptr || self->pw_->stream == nullptr) {
    return;
  }
  const int n = self->pw_->process_logs;
  if (n < 8) {
    FacCameraLog("pw camera process enter n=%d", n);
  }
  pw_buffer* buffer = nullptr;
  while (true) {
    pw_buffer* next = pw_stream_dequeue_buffer(self->pw_->stream);
    if (next == nullptr) {
      break;
    }
    if (buffer != nullptr) {
      pw_stream_queue_buffer(self->pw_->stream, buffer);
    }
    buffer = next;
  }
  if (buffer == nullptr || buffer->buffer == nullptr ||
      buffer->buffer->n_datas < 1) {
    if (n < 8) {
      FacCameraLog("pw camera process empty n=%d", n);
    }
    self->pw_->process_logs++;
    if (buffer != nullptr) {
      pw_stream_queue_buffer(self->pw_->stream, buffer);
    }
    return;
  }
  spa_data* datas = buffer->buffer->datas;
  if (datas[0].chunk != nullptr &&
      (datas[0].chunk->size == 0 ||
       (datas[0].chunk->flags & SPA_CHUNK_FLAG_CORRUPTED) != 0)) {
    if (self->pw_->process_logs < 5) {
      FacCameraLog("pw camera skip empty chunk size=%u flags=%u",
                   datas[0].chunk->size, datas[0].chunk->flags);
      self->pw_->process_logs++;
    }
    pw_stream_queue_buffer(self->pw_->stream, buffer);
    return;
  }
  auto dma_sync = [](int fd, uint64_t flags) {
    if (fd < 0) {
      return;
    }
    struct dma_buf_sync sync {};
    sync.flags = flags;
    ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);
  };
  const bool log_frame = self->pw_->process_logs < 5;
  if (log_frame) {
    FacCameraLog(
        "pw camera process n=%d type=%u fd=%ld data=%p max=%zu stride=%d off=%u size=%u flags=%u",
        self->pw_->process_logs, datas[0].type, static_cast<long>(datas[0].fd),
        datas[0].data, static_cast<size_t>(datas[0].maxsize),
        datas[0].chunk != nullptr ? datas[0].chunk->stride : 0,
        datas[0].chunk != nullptr ? datas[0].chunk->offset : 0,
        datas[0].chunk != nullptr ? datas[0].chunk->size : 0,
        datas[0].chunk != nullptr ? datas[0].chunk->flags : 0);
    self->pw_->process_logs++;
  }
  const uint8_t* src = nullptr;
  size_t length = 0;
  int stride = 0;
  void* mapped = nullptr;
  size_t mapped_size = 0;
  if (datas[0].data != nullptr) {
    src = static_cast<const uint8_t*>(datas[0].data);
    if (datas[0].chunk != nullptr) {
      src += datas[0].chunk->offset;
      length = datas[0].chunk->size > 0 ? datas[0].chunk->size
                                        : datas[0].maxsize;
      stride = datas[0].chunk->stride;
    } else {
      length = datas[0].maxsize;
    }
    if (log_frame) {
      FacCameraLog("pw camera mem px=%02x %02x %02x %02x", src[0], src[1],
                   src[2], src[3]);
    }
  } else if (datas[0].fd >= 0 && datas[0].maxsize > 0) {
    const off_t off = static_cast<off_t>(datas[0].mapoffset);
    mapped = mmap(nullptr, datas[0].maxsize, PROT_READ, MAP_SHARED, datas[0].fd,
                  off);
    if (mapped == MAP_FAILED) {
      mapped = mmap(nullptr, datas[0].maxsize, PROT_READ, MAP_PRIVATE,
                    datas[0].fd, off);
    }
    if (mapped != MAP_FAILED) {
      mapped_size = datas[0].maxsize;
      if (datas[0].type == SPA_DATA_DmaBuf) {
        dma_sync(static_cast<int>(datas[0].fd),
                 DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ);
      }
      src = static_cast<const uint8_t*>(mapped);
      if (datas[0].chunk != nullptr) {
        src += datas[0].chunk->offset;
        length = datas[0].chunk->size > 0 ? datas[0].chunk->size
                                          : datas[0].maxsize;
        stride = datas[0].chunk->stride;
      } else {
        length = datas[0].maxsize;
      }
      if (log_frame) {
        FacCameraLog("pw camera mapped px=%02x %02x %02x %02x live=%ld", src[0],
                     src[1], src[2], src[3],
                     static_cast<long>(self->live_frames_.load()));
      }
    } else if (log_frame) {
      FacCameraLog("pw camera mmap failed errno=%d", errno);
    }
  }
  if (src != nullptr) {
    if (self->muted_.load() || !self->enabled_.load()) {
      std::lock_guard<std::mutex> lock(self->mutex_);
      self->FillBlackLocked();
    } else if (self->pixelformat_ != 0) {
      self->bytesperline_ = stride;
      self->ConvertFrame(src, length);
    } else if (self->pw_->spa_format == SPA_VIDEO_FORMAT_RGBx ||
               self->pw_->spa_format == SPA_VIDEO_FORMAT_RGBA ||
               self->pw_->spa_format == SPA_VIDEO_FORMAT_BGRx ||
               self->pw_->spa_format == SPA_VIDEO_FORMAT_BGRA) {
      std::lock_guard<std::mutex> lock(self->mutex_);
      const int src_w = self->pw_->src_w;
      const int src_h = self->pw_->src_h;
      const int out_w = self->width_;
      const int out_h = self->height_;
      const size_t bytes = static_cast<size_t>(out_w) * out_h * 4;
      if (self->front_.size() != bytes) {
        self->front_.assign(bytes, 0);
      }
      const bool bgr = self->pw_->spa_format == SPA_VIDEO_FORMAT_BGRx ||
                       self->pw_->spa_format == SPA_VIDEO_FORMAT_BGRA;
      const int row_stride = stride > 0 ? stride : src_w * 4;
      for (int y = 0; y < out_h; y++) {
        const int src_y = y * src_h / std::max(1, out_h);
        const uint8_t* row =
            src + static_cast<ptrdiff_t>(row_stride) * src_y;
        uint8_t* out =
            self->front_.data() + static_cast<size_t>(y) * out_w * 4;
        for (int x = 0; x < out_w; x++) {
          const int src_x = x * src_w / std::max(1, out_w);
          const uint8_t* px = row + src_x * 4;
          out[x * 4 + 0] = bgr ? px[2] : px[0];
          out[x * 4 + 1] = px[1];
          out[x * 4 + 2] = bgr ? px[0] : px[2];
          out[x * 4 + 3] = 255;
        }
      }
      if (LooksLiveRgba(self->front_.data(), self->front_.size())) {
        self->processor_.Process(self->front_.data(), out_w, out_h);
        self->live_frames_.fetch_add(1);
      } else {
        self->FillBlackLocked();
      }
    }
  }
  if (mapped != nullptr && mapped != MAP_FAILED) {
    if (datas[0].type == SPA_DATA_DmaBuf) {
      dma_sync(static_cast<int>(datas[0].fd),
               DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ);
    }
    munmap(mapped, mapped_size);
  }
  self->frame_count_.fetch_add(1);
  pw_stream_queue_buffer(self->pw_->stream, buffer);
  if (log_frame) {
    FacCameraLog("pw camera queued live=%ld",
                 static_cast<long>(self->live_frames_.load()));
  }
  self->MarkTexture();
#else
  (void)data;
#endif
}

bool CameraGraph::TrySetFormat(uint32_t fourcc, int width, int height,
                               v4l2_format* out) {
  v4l2_format fmt = {};
  fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  ioctl(fd_, VIDIOC_G_FMT, &fmt);
  fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  fmt.fmt.pix.pixelformat = fourcc;
  fmt.fmt.pix.field = V4L2_FIELD_NONE;
  if (width > 0 && height > 0) {
    fmt.fmt.pix.width = static_cast<uint32_t>(width);
    fmt.fmt.pix.height = static_cast<uint32_t>(height);
  }
  if (ioctl(fd_, VIDIOC_S_FMT, &fmt) < 0) {
    FacCameraLog("S_FMT failed fourcc=%u %dx%d errno=%d", fourcc, width, height,
                 errno);
    return false;
  }
  if (fmt.fmt.pix.pixelformat != fourcc) {
    FacCameraLog("S_FMT fourcc mismatch want=%u got=%u", fourcc,
                 fmt.fmt.pix.pixelformat);
    return false;
  }
  *out = fmt;
  return true;
}

void CameraGraph::CaptureLoop() {
  while (running_.load()) {
    pollfd pfd = {};
    pfd.fd = fd_;
    pfd.events = POLLIN;
    const int ready = poll(&pfd, 1, 100);
    if (!running_.load()) {
      break;
    }
    if (ready <= 0) {
      continue;
    }
    v4l2_buffer buf = {};
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    if (ioctl(fd_, VIDIOC_DQBUF, &buf) < 0) {
      if (errno == EAGAIN || errno == EINTR) {
        continue;
      }
      break;
    }
    if (!running_.load()) {
      ioctl(fd_, VIDIOC_QBUF, &buf);
      break;
    }
    frame_count_.fetch_add(1);
    if (muted_.load() || !enabled_.load()) {
      std::lock_guard<std::mutex> lock(mutex_);
      FillBlackLocked();
    } else if (buf.index < buffers_.size()) {
      ConvertFrame(static_cast<const uint8_t*>(buffers_[buf.index].start),
                   buf.bytesused);
    }
    ioctl(fd_, VIDIOC_QBUF, &buf);
    MarkTexture();
  }
}

void CameraGraph::MarkTexture() {
  if (textures_ == nullptr || texture_ == nullptr) {
    return;
  }
  if (mark_pending_.exchange(true)) {
    return;
  }
  g_idle_add(
      [](gpointer user) -> gboolean {
        auto* graph = static_cast<CameraGraph*>(user);
        graph->mark_pending_.store(false);
        if (graph->textures_ != nullptr && graph->texture_ != nullptr) {
          fl_texture_registrar_mark_texture_frame_available(
              graph->textures_, FL_TEXTURE(graph->texture_));
        }
        return G_SOURCE_REMOVE;
      },
      this);
}

void CameraGraph::ConvertFrame(const uint8_t* src, size_t length) {
  std::lock_guard<std::mutex> lock(mutex_);
  const size_t bytes = static_cast<size_t>(width_) * height_ * 4;
  if (front_.size() != bytes) {
    front_.assign(bytes, 0);
  }
  uint8_t* dst = front_.data();
  const int stride = bytesperline_ > 0 ? bytesperline_ : width_ * 2;
  if (pixelformat_ == V4L2_PIX_FMT_MJPEG || pixelformat_ == V4L2_PIX_FMT_JPEG) {
    if (!DecodeJpegRgba(src, length, width_, height_, dst)) {
      FillBlackLocked();
      return;
    }
  } else if (pixelformat_ == V4L2_PIX_FMT_RGB24) {
    const int row_stride = bytesperline_ > 0 ? bytesperline_ : width_ * 3;
    for (int y = 0; y < height_; y++) {
      const uint8_t* row = src + static_cast<ptrdiff_t>(row_stride) * y;
      uint8_t* out = dst + static_cast<size_t>(y) * width_ * 4;
      for (int x = 0; x < width_; x++) {
        out[x * 4 + 0] = row[x * 3 + 0];
        out[x * 4 + 1] = row[x * 3 + 1];
        out[x * 4 + 2] = row[x * 3 + 2];
        out[x * 4 + 3] = 255;
      }
    }
  } else if (pixelformat_ == V4L2_PIX_FMT_BGR24) {
    const int row_stride = bytesperline_ > 0 ? bytesperline_ : width_ * 3;
    for (int y = 0; y < height_; y++) {
      const uint8_t* row = src + static_cast<ptrdiff_t>(row_stride) * y;
      uint8_t* out = dst + static_cast<size_t>(y) * width_ * 4;
      for (int x = 0; x < width_; x++) {
        out[x * 4 + 0] = row[x * 3 + 2];
        out[x * 4 + 1] = row[x * 3 + 1];
        out[x * 4 + 2] = row[x * 3 + 0];
        out[x * 4 + 3] = 255;
      }
    }
  } else if (pixelformat_ == V4L2_PIX_FMT_NV12) {
    const int y_stride = bytesperline_ > 0 ? bytesperline_ : width_;
    const uint8_t* uv = src + static_cast<ptrdiff_t>(y_stride) * height_;
    for (int y = 0; y < height_; y++) {
      const uint8_t* y_row = src + static_cast<ptrdiff_t>(y_stride) * y;
      const uint8_t* uv_row =
          uv + static_cast<ptrdiff_t>(y_stride) * (y / 2);
      uint8_t* out = dst + static_cast<size_t>(y) * width_ * 4;
      for (int x = 0; x < width_; x++) {
        const int c = y_row[x] - 16;
        const int d = uv_row[x & ~1] - 128;
        const int e = uv_row[(x & ~1) + 1] - 128;
        out[x * 4 + 0] = Clamp((298 * c + 409 * e + 128) >> 8);
        out[x * 4 + 1] = Clamp((298 * c - 100 * d - 208 * e + 128) >> 8);
        out[x * 4 + 2] = Clamp((298 * c + 516 * d + 128) >> 8);
        out[x * 4 + 3] = 255;
      }
    }
  } else if (pixelformat_ == V4L2_PIX_FMT_GREY) {
    const int row_stride = bytesperline_ > 0 ? bytesperline_ : width_;
    for (int y = 0; y < height_; y++) {
      const uint8_t* row = src + static_cast<ptrdiff_t>(row_stride) * y;
      uint8_t* out = dst + static_cast<size_t>(y) * width_ * 4;
      for (int x = 0; x < width_; x++) {
        const uint8_t g = row[x];
        out[x * 4 + 0] = g;
        out[x * 4 + 1] = g;
        out[x * 4 + 2] = g;
        out[x * 4 + 3] = 255;
      }
    }
  } else {
    for (int y = 0; y < height_; y++) {
      const uint8_t* row = src + static_cast<ptrdiff_t>(stride) * y;
      uint8_t* out = dst + static_cast<size_t>(y) * width_ * 4;
      for (int x = 0; x + 1 < width_; x += 2) {
        const int y0 = row[x * 2 + 0];
        const int u = row[x * 2 + 1];
        const int y1 = row[x * 2 + 2];
        const int v = row[x * 2 + 3];
        const int c0 = y0 - 16;
        const int c1 = y1 - 16;
        const int d = u - 128;
        const int e = v - 128;
        out[x * 4 + 0] = Clamp((298 * c0 + 409 * e + 128) >> 8);
        out[x * 4 + 1] = Clamp((298 * c0 - 100 * d - 208 * e + 128) >> 8);
        out[x * 4 + 2] = Clamp((298 * c0 + 516 * d + 128) >> 8);
        out[x * 4 + 3] = 255;
        out[(x + 1) * 4 + 0] = Clamp((298 * c1 + 409 * e + 128) >> 8);
        out[(x + 1) * 4 + 1] = Clamp((298 * c1 - 100 * d - 208 * e + 128) >> 8);
        out[(x + 1) * 4 + 2] = Clamp((298 * c1 + 516 * d + 128) >> 8);
        out[(x + 1) * 4 + 3] = 255;
      }
    }
  }
  processor_.Process(front_.data(), width_, height_);
  const bool live = LooksLiveRgba(front_.data(), front_.size());
  if (live) {
    live_frames_.fetch_add(1);
  }
  static std::atomic<int> convert_logs{0};
  if (convert_logs.fetch_add(1) < 4 && !front_.empty()) {
    FacCameraLog("convert fourcc=%u %dx%d len=%zu live=%d px=%02x %02x %02x %02x",
                 pixelformat_, width_, height_, length, live ? 1 : 0, front_[0],
                 front_[1], front_[2], front_[3]);
  }
}

void CameraGraph::FillBlackLocked() {
  const size_t bytes = static_cast<size_t>(width_) * height_ * 4;
  if (front_.size() != bytes) {
    front_.assign(bytes, 0);
  }
  for (size_t i = 0; i < bytes; i += 4) {
    front_[i] = 0;
    front_[i + 1] = 0;
    front_[i + 2] = 0;
    front_[i + 3] = 255;
  }
}

gboolean CameraGraph::CopyPixels(const uint8_t** buffer,
                                 uint32_t* width,
                                 uint32_t* height,
                                 GError** error) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (front_.empty()) {
    if (error != nullptr) {
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "no frame");
    }
    return FALSE;
  }
  display_ = front_;
  *buffer = display_.data();
  *width = static_cast<uint32_t>(width_);
  *height = static_cast<uint32_t>(height_);
  return TRUE;
}
