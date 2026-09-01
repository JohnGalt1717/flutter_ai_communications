#include "camera_graph.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstring>
#include <vector>

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
         fourcc == V4L2_PIX_FMT_RGB24 || fourcc == V4L2_PIX_FMT_BGR24;
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

CameraGraph::CameraGraph(FlTextureRegistrar* textures) : textures_(textures) {}

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
    const int fd = open(path.c_str(), O_RDWR | O_NONBLOCK);
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
  return cameras;
}

std::string CameraGraph::RequestPermission() {
  bool saw_capture = false;
  bool opened = false;
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
    opened = true;
    close(fd);
  }
  if (!saw_capture && denied) {
    return "denied";
  }
  (void)opened;
  return "granted";
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

bool CameraGraph::StartCapture(const std::string& camera_id,
                               int width,
                               int height,
                               int frame_rate) {
  StopCapture();
  std::string path = camera_id;
  if (path.empty()) {
    FlValue* cameras = Enumerate();
    if (fl_value_get_length(cameras) > 0) {
      FlValue* first = fl_value_get_list_value(cameras, 0);
      FlValue* id = fl_value_lookup_string(first, "id");
      if (id != nullptr) {
        path = fl_value_get_string(id);
      }
    }
    fl_value_unref(cameras);
  }
  if (path.empty()) {
    return false;
  }
  fd_ = open(path.c_str(), O_RDWR);
  if (fd_ < 0 || !IsCaptureDevice(fd_)) {
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
    return false;
  }
  camera_id_ = path;
  const uint32_t candidates[] = {V4L2_PIX_FMT_YUYV, V4L2_PIX_FMT_NV12,
                                 V4L2_PIX_FMT_RGB24, V4L2_PIX_FMT_BGR24};
  const int sizes[][2] = {{width, height}, {1280, 720}, {640, 480}, {0, 0}};
  bool formatted = false;
  v4l2_format fmt = {};
  for (uint32_t fourcc : candidates) {
    for (const auto& size : sizes) {
      if (TrySetFormat(fourcc, size[0], size[1], &fmt) &&
          CanConvert(fmt.fmt.pix.pixelformat)) {
        formatted = true;
        pixelformat_ = fmt.fmt.pix.pixelformat;
        break;
      }
    }
    if (formatted) {
      break;
    }
  }
  if (!formatted) {
    close(fd_);
    fd_ = -1;
    return false;
  }
  width_ = static_cast<int>(fmt.fmt.pix.width);
  height_ = static_cast<int>(fmt.fmt.pix.height);
  bytesperline_ = static_cast<int>(fmt.fmt.pix.bytesperline);
  frame_rate_ = frame_rate;
  v4l2_streamparm parm = {};
  parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (ioctl(fd_, VIDIOC_G_PARM, &parm) == 0 &&
      (parm.parm.capture.capability & V4L2_CAP_TIMEPERFRAME)) {
    parm.parm.capture.timeperframe.numerator = 1;
    parm.parm.capture.timeperframe.denominator =
        static_cast<uint32_t>(frame_rate);
    ioctl(fd_, VIDIOC_S_PARM, &parm);
    if (parm.parm.capture.timeperframe.numerator != 0) {
      frame_rate_ = static_cast<int>(
          parm.parm.capture.timeperframe.denominator /
          parm.parm.capture.timeperframe.numerator);
    }
  }
  v4l2_requestbuffers req = {};
  req.count = 4;
  req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  req.memory = V4L2_MEMORY_MMAP;
  if (ioctl(fd_, VIDIOC_REQBUFS, &req) < 0 || req.count < 2) {
    close(fd_);
    fd_ = -1;
    return false;
  }
  buffers_.resize(req.count);
  for (uint32_t i = 0; i < req.count; i++) {
    v4l2_buffer buf = {};
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    buf.index = i;
    if (ioctl(fd_, VIDIOC_QUERYBUF, &buf) < 0) {
      StopCapture();
      return false;
    }
    buffers_[i].length = buf.length;
    buffers_[i].start =
        mmap(nullptr, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd_,
             buf.m.offset);
    if (buffers_[i].start == MAP_FAILED) {
      StopCapture();
      return false;
    }
    if (ioctl(fd_, VIDIOC_QBUF, &buf) < 0) {
      StopCapture();
      return false;
    }
  }
  v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (ioctl(fd_, VIDIOC_STREAMON, &type) < 0) {
    StopCapture();
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    FillBlackLocked();
  }
  frame_count_.store(0);
  live_frames_.store(0);
  running_.store(true);
  capture_thread_ = std::thread([this]() { CaptureLoop(); });
  return true;
}

bool CameraGraph::TrySetFormat(uint32_t fourcc, int width, int height,
                               v4l2_format* out) {
  v4l2_format fmt = {};
  fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  fmt.fmt.pix.pixelformat = fourcc;
  fmt.fmt.pix.field = V4L2_FIELD_NONE;
  if (width > 0 && height > 0) {
    fmt.fmt.pix.width = static_cast<uint32_t>(width);
    fmt.fmt.pix.height = static_cast<uint32_t>(height);
  }
  if (ioctl(fd_, VIDIOC_S_FMT, &fmt) < 0) {
    return false;
  }
  if (fmt.fmt.pix.pixelformat != fourcc) {
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
      ConvertFrame(static_cast<const uint8_t*>(buffers_[buf.index].start));
    }
    ioctl(fd_, VIDIOC_QBUF, &buf);
    if (textures_ != nullptr && texture_ != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(textures_,
                                                        FL_TEXTURE(texture_));
    }
  }
}

void CameraGraph::ConvertFrame(const uint8_t* src) {
  std::lock_guard<std::mutex> lock(mutex_);
  const size_t bytes = static_cast<size_t>(width_) * height_ * 4;
  if (front_.size() != bytes) {
    front_.assign(bytes, 0);
  }
  uint8_t* dst = front_.data();
  const int stride = bytesperline_ > 0 ? bytesperline_ : width_ * 2;
  if (pixelformat_ == V4L2_PIX_FMT_RGB24) {
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
  for (size_t i = 0; i + 3 < front_.size(); i += 64) {
    if (front_[i] > 8 || front_[i + 1] > 8 || front_[i + 2] > 8) {
      live_frames_.fetch_add(1);
      break;
    }
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
