#include "camera_graph.h"

#include <errno.h>
#include <fcntl.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gio/gio.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <condition_variable>
#include <cstring>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <set>
#include <thread>
#include <tuple>
#include <vector>

namespace {

void FacLog(const char* fmt, ...) {
  const char* path = std::getenv("FAC_NATIVE_LOG");
  if (path == nullptr || path[0] == '\0') {
    return;
  }
  FILE* file = std::fopen(path, "a");
  if (file == nullptr) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  std::vfprintf(file, fmt, args);
  va_end(args);
  std::fputc('\n', file);
  std::fclose(file);
}

// UVC VIDIOC_S_FMT / STREAMON can block the GTK thread forever (LifeCam).
// The worker owns a heap copy of the ioctl argument and, on timeout, the
// descriptor. The caller copies results back only after a timely completion.
int IoctlTimed(int* fd, unsigned long request, void* arg, size_t arg_size,
               int timeout_ms) {
  if (fd == nullptr || *fd < 0) {
    errno = EBADF;
    return -1;
  }
  struct Job {
    std::mutex mu;
    std::condition_variable cv;
    int result = -1;
    bool finished = false;
    bool timed_out = false;
    int fd = -1;
    std::vector<uint8_t> storage;
    void* arg = nullptr;
  };
  const auto job = std::make_shared<Job>();
  job->fd = *fd;
  if (arg != nullptr && arg_size > 0) {
    job->storage.resize(arg_size);
    std::memcpy(job->storage.data(), arg, arg_size);
    job->arg = job->storage.data();
  }
  std::thread worker([job, request] {
    const int r = ioctl(job->fd, request, job->arg);
    bool abandon = false;
    {
      std::lock_guard<std::mutex> lock(job->mu);
      job->result = r;
      job->finished = true;
      abandon = job->timed_out;
    }
    job->cv.notify_one();
    if (abandon && job->fd >= 0) {
      close(job->fd);
    }
  });
  std::unique_lock<std::mutex> lock(job->mu);
  if (!job->cv.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                        [&] { return job->finished; })) {
    job->timed_out = true;
    lock.unlock();
    // Do not close() here: close on a fd with a stuck UVC ioctl blocks
    // this thread until the driver returns, which is the hang we bound.
    *fd = -1;
    worker.detach();
    errno = ETIMEDOUT;
    return -1;
  }
  const int result = job->result;
  lock.unlock();
  worker.join();
  if (arg != nullptr && arg_size > 0 && job->storage.size() == arg_size) {
    std::memcpy(arg, job->storage.data(), arg_size);
  }
  return result;
}

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

bool IsCaptureDevice(int* fd, v4l2_capability* out = nullptr) {
  v4l2_capability cap = {};
  if (IoctlTimed(fd, VIDIOC_QUERYCAP, &cap, sizeof(cap), 250) < 0) {
    return false;
  }
  const uint32_t caps =
      cap.device_caps != 0 ? cap.device_caps : cap.capabilities;
  if ((caps & V4L2_CAP_VIDEO_CAPTURE) == 0 ||
      (caps & V4L2_CAP_STREAMING) == 0) {
    return false;
  }
  if (out != nullptr) {
    *out = cap;
  }
  return true;
}

bool CanConvert(uint32_t fourcc) {
  return fourcc == V4L2_PIX_FMT_YUYV || fourcc == V4L2_PIX_FMT_NV12 ||
         fourcc == V4L2_PIX_FMT_RGB24 || fourcc == V4L2_PIX_FMT_BGR24 ||
         fourcc == V4L2_PIX_FMT_MJPEG || fourcc == V4L2_PIX_FMT_JPEG;
}

int FourccRank(uint32_t fourcc) {
  switch (fourcc) {
    case V4L2_PIX_FMT_YUYV:
      return 0;
    case V4L2_PIX_FMT_NV12:
      return 1;
    case V4L2_PIX_FMT_RGB24:
      return 2;
    case V4L2_PIX_FMT_BGR24:
      return 3;
    case V4L2_PIX_FMT_MJPEG:
    case V4L2_PIX_FMT_JPEG:
      return 4;
    default:
      return 9;
  }
}

struct NativeMode {
  int width = 0;
  int height = 0;
  int frame_rate = 30;
  uint32_t fourcc = 0;
};

int ModePixels(const NativeMode& mode) { return mode.width * mode.height; }

int IntervalFps(const v4l2_fract& fract) {
  if (fract.numerator == 0) {
    return 30;
  }
  const int fps = static_cast<int>(fract.denominator / fract.numerator);
  return fps < 1 ? 1 : fps;
}

std::vector<NativeMode> CollectModes(int fd) {
  std::vector<NativeMode> modes;
  if (fd < 0) {
    return modes;
  }
  v4l2_fmtdesc desc = {};
  desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  for (desc.index = 0; ioctl(fd, VIDIOC_ENUM_FMT, &desc) == 0; desc.index++) {
    if (!CanConvert(desc.pixelformat)) {
      continue;
    }
    v4l2_frmsizeenum size = {};
    size.pixel_format = desc.pixelformat;
    for (size.index = 0; ioctl(fd, VIDIOC_ENUM_FRAMESIZES, &size) == 0;
         size.index++) {
      std::vector<std::pair<int, int>> dims;
      if (size.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
        dims.emplace_back(static_cast<int>(size.discrete.width),
                          static_cast<int>(size.discrete.height));
      } else {
        const auto& sw = size.stepwise;
        dims.emplace_back(static_cast<int>(sw.min_width),
                          static_cast<int>(sw.min_height));
        dims.emplace_back(static_cast<int>(sw.max_width),
                          static_cast<int>(sw.max_height));
        if (sw.min_width <= 1280 && 1280 <= sw.max_width &&
            sw.min_height <= 720 && 720 <= sw.max_height) {
          dims.emplace_back(1280, 720);
        }
      }
      for (const auto& dim : dims) {
        v4l2_frmivalenum ival = {};
        ival.pixel_format = desc.pixelformat;
        ival.width = static_cast<uint32_t>(dim.first);
        ival.height = static_cast<uint32_t>(dim.second);
        bool any = false;
        for (ival.index = 0; ioctl(fd, VIDIOC_ENUM_FRAMEINTERVALS, &ival) == 0;
             ival.index++) {
          int fps = 30;
          if (ival.type == V4L2_FRMIVAL_TYPE_DISCRETE) {
            fps = IntervalFps(ival.discrete);
          }
          modes.push_back({dim.first, dim.second, fps, desc.pixelformat});
          any = true;
        }
        if (!any) {
          modes.push_back({dim.first, dim.second, 30, desc.pixelformat});
        }
      }
    }
  }
  return modes;
}

// UVC MJPEG often omits Huffman tables. gdk-pixbuf needs them.
const uint8_t kJpegDht[] = {
    0xff, 0xc4, 0x01, 0xa2, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02,
    0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x01, 0x00, 0x03,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
    0x0a, 0x0b, 0x10, 0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05,
    0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7d, 0x01, 0x02, 0x03, 0x00, 0x04,
    0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22,
    0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15,
    0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17,
    0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36,
    0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a,
    0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66,
    0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a,
    0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95,
    0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8,
    0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2,
    0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5,
    0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7,
    0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9,
    0xfa, 0x11, 0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05,
    0x04, 0x04, 0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04,
    0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22,
    0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33,
    0x52, 0xf0, 0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25,
    0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x35, 0x36,
    0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a,
    0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66,
    0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a,
    0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94,
    0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba,
    0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4,
    0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7,
    0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa};

std::vector<uint8_t> JpegWithDht(const uint8_t* src, size_t len) {
  std::vector<uint8_t> out;
  if (src == nullptr || len < 4) {
    return out;
  }
  bool has_dht = false;
  size_t sos = len;
  for (size_t i = 0; i + 1 < len; i++) {
    if (src[i] != 0xff) {
      continue;
    }
    const uint8_t marker = src[i + 1];
    if (marker == 0xc4) {
      has_dht = true;
    }
    if (marker == 0xda) {
      sos = i;
      break;
    }
  }
  if (has_dht || sos >= len) {
    out.assign(src, src + len);
    return out;
  }
  out.reserve(len + sizeof(kJpegDht));
  out.insert(out.end(), src, src + sos);
  out.insert(out.end(), kJpegDht, kJpegDht + sizeof(kJpegDht));
  out.insert(out.end(), src + sos, src + len);
  return out;
}

NativeMode NearestMode(const std::vector<NativeMode>& modes, int req_w,
                       int req_h, int req_fps) {
  NativeMode best = modes.front();
  const int req = std::max(1, req_w * req_h);
  const int want_fps = req_fps > 0 ? req_fps : 30;
  auto better = [&](const NativeMode& a, const NativeMode& b) {
    const int pa = ModePixels(a);
    const int pb = ModePixels(b);
    const bool a_hi = pa >= req;
    const bool b_hi = pb >= req;
    if (a_hi != b_hi) {
      return a_hi;
    }
    if (pa != pb) {
      return a_hi ? pa < pb : pa > pb;
    }
    const int da = std::abs(a.frame_rate - want_fps);
    const int db = std::abs(b.frame_rate - want_fps);
    if (da != db) {
      return da < db;
    }
    const bool a_fps_hi = a.frame_rate >= want_fps;
    const bool b_fps_hi = b.frame_rate >= want_fps;
    if (a_fps_hi != b_fps_hi) {
      return a_fps_hi;
    }
    return FourccRank(a.fourcc) < FourccRank(b.fourcc);
  };
  for (const auto& mode : modes) {
    if (better(mode, best)) {
      best = mode;
    }
  }
  return best;
}

FlValue* ModesToValue(const std::vector<NativeMode>& modes) {
  FlValue* list = fl_value_new_list();
  std::set<std::tuple<int, int, int>> seen;
  for (const auto& mode : modes) {
    if (mode.width < 1 || mode.height < 1) {
      continue;
    }
    if (!seen.insert({mode.width, mode.height, mode.frame_rate}).second) {
      continue;
    }
    FlValue* item = fl_value_new_map();
    fl_value_set_string_take(item, "width", fl_value_new_int(mode.width));
    fl_value_set_string_take(item, "height", fl_value_new_int(mode.height));
    fl_value_set_string_take(item, "frameRate",
                             fl_value_new_int(mode.frame_rate));
    fl_value_append_take(list, item);
  }
  if (fl_value_get_length(list) == 0) {
    FlValue* item = fl_value_new_map();
    fl_value_set_string_take(item, "width", fl_value_new_int(1280));
    fl_value_set_string_take(item, "height", fl_value_new_int(720));
    fl_value_set_string_take(item, "frameRate", fl_value_new_int(30));
    fl_value_append_take(list, item);
  }
  return list;
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
  alive_->store(false);
  CancelPendingMark();
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
  std::lock_guard<std::mutex> lock(mutex_);
  if (front_.empty()) {
    if (width_ < 1) {
      width_ = 1280;
    }
    if (height_ < 1) {
      height_ = 720;
    }
    FillBlackLocked();
  }
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
  std::lock_guard<std::recursive_mutex> lifecycle(lifecycle_);
  FlValue* cameras = fl_value_new_list();
  const bool streaming = running_.load();
  for (int i = 0; i < 64; i++) {
    const std::string path = "/dev/video" + std::to_string(i);
    std::string name;
    std::string facing;
    std::vector<NativeMode> native_modes;
    if (streaming && path == camera_id_ && !cached_name_.empty()) {
      name = cached_name_;
      facing = cached_facing_;
      for (const auto& mode : cached_modes_) {
        native_modes.push_back(
            {mode.width, mode.height, mode.frame_rate, 0});
      }
    } else {
      int fd = open(path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
      if (fd < 0) {
        continue;
      }
      v4l2_capability cap = {};
      if (!IsCaptureDevice(&fd, &cap)) {
        if (fd >= 0) {
          close(fd);
        }
        continue;
      }
      native_modes = CollectModes(fd);
      if (fd >= 0) {
        close(fd);
      }
      name = reinterpret_cast<const char*>(cap.card);
      const std::string bus = reinterpret_cast<const char*>(cap.bus_info);
      facing = FacingFor(name, bus);
    }
    FlValue* camera = fl_value_new_map();
    fl_value_set_string_take(camera, "id", fl_value_new_string(path.c_str()));
    fl_value_set_string_take(camera, "name",
                             fl_value_new_string(name.c_str()));
    fl_value_set_string_take(camera, "facing",
                             fl_value_new_string(facing.c_str()));
    fl_value_set_string_take(camera, "modes", ModesToValue(native_modes));
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
    int fd = open(path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
      if (errno == EACCES || errno == EPERM) {
        denied = true;
      }
      continue;
    }
    if (!IsCaptureDevice(&fd)) {
      if (fd >= 0) {
        close(fd);
      }
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

bool CameraGraph::StartCancelled(uint64_t epoch) const {
  return epoch != lifecycle_epoch_.load();
}

uint64_t CameraGraph::LifecycleEpoch() const {
  return lifecycle_epoch_.load();
}

FlValue* CameraGraph::Start(const std::string& camera_id,
                            int width,
                            int height,
                            int frame_rate,
                            bool enabled,
                            bool muted,
                            uint64_t epoch) {
  std::lock_guard<std::recursive_mutex> lifecycle(lifecycle_);
  FlValue* result = fl_value_new_map();
  if (StartCancelled(epoch)) {
    fl_value_set_string_take(result, "status",
                             fl_value_new_string("unavailable"));
    return result;
  }
  EnsureTexture();
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
    RequestTextureMark();
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
  if (StartCancelled(epoch)) {
    StopCapture();
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

void CameraGraph::Stop() {
  lifecycle_epoch_.fetch_add(1);
  std::lock_guard<std::recursive_mutex> lifecycle(lifecycle_);
  StopCapture();
}

std::string CameraGraph::SetProcessor(FlValue* args) {
  processor_.SetOnUnavailable(on_processor_unavailable_);
  return processor_.Apply(args);
}

void CameraGraph::SetOnProcessorUnavailable(std::function<void()> callback) {
  on_processor_unavailable_ = std::move(callback);
  processor_.SetOnUnavailable(on_processor_unavailable_);
}

void CameraGraph::Select(const std::string& camera_id) {
  std::lock_guard<std::recursive_mutex> lifecycle(lifecycle_);
  FlValue* result =
      Start(camera_id, request_width_, request_height_, request_frame_rate_,
            enabled_.load(), muted_.load(), LifecycleEpoch());
  fl_value_unref(result);
}

void CameraGraph::SetEnabled(bool enabled) {
  if (!enabled) {
    lifecycle_epoch_.fetch_add(1);
  }
  std::lock_guard<std::recursive_mutex> lifecycle(lifecycle_);
  enabled_.store(enabled);
  if (!enabled) {
    StopCapture();
    std::lock_guard<std::mutex> lock(mutex_);
    FillBlackLocked();
    RequestTextureMark();
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
  RequestTextureMark();
}

void CameraGraph::SetMarksAllowed(bool allowed) {
  marks_allowed_.store(allowed);
}

void CameraGraph::RefreshTexture() { RequestTextureMark(); }

void CameraGraph::CancelPendingMark() {
  const guint id = mark_source_.exchange(0);
  if (id != 0) {
    g_source_remove(id);
  }
  mark_pending_.store(false);
}

void CameraGraph::RequestTextureMark() {
  if (!alive_->load() || !marks_allowed_.load()) {
    return;
  }
  bool expected = false;
  if (!mark_pending_.compare_exchange_strong(expected, true)) {
    return;
  }
  struct Mark {
    CameraGraph* graph;
    std::shared_ptr<std::atomic<bool>> alive;
    uint64_t epoch;
  };
  auto* mark = new Mark{this, alive_, texture_epoch_.load()};
  const guint id = g_idle_add_full(
      G_PRIORITY_DEFAULT_IDLE,
      [](gpointer data) -> gboolean {
        auto* mark = static_cast<Mark*>(data);
        if (!mark->alive || !mark->alive->load() || mark->graph == nullptr) {
          return G_SOURCE_REMOVE;
        }
        mark->graph->mark_source_.store(0);
        mark->graph->mark_pending_.store(false);
        if (mark->graph->marks_allowed_.load() &&
            mark->graph->texture_epoch_.load() == mark->epoch &&
            mark->graph->textures_ != nullptr &&
            mark->graph->texture_ != nullptr) {
          fl_texture_registrar_mark_texture_frame_available(
              mark->graph->textures_, FL_TEXTURE(mark->graph->texture_));
        }
        return G_SOURCE_REMOVE;
      },
      mark,
      [](gpointer data) { delete static_cast<Mark*>(data); });
  if (!alive_->load()) {
    g_source_remove(id);
    mark_pending_.store(false);
    return;
  }
  mark_source_.store(id);
}

void CameraGraph::StopCapture() {
  texture_epoch_.fetch_add(1);
  CancelPendingMark();
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
  fd_ = open(path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
  v4l2_capability cap = {};
  if (fd_ < 0 || !IsCaptureDevice(&fd_, &cap)) {
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
    return false;
  }
  camera_id_ = path;
  cached_name_ = reinterpret_cast<const char*>(cap.card);
  cached_facing_ = FacingFor(cached_name_,
                             reinterpret_cast<const char*>(cap.bus_info));
  const auto available = CollectModes(fd_);
  cached_modes_.clear();
  {
    std::set<std::tuple<int, int, int>> seen;
    for (const auto& mode : available) {
      if (!seen.insert({mode.width, mode.height, mode.frame_rate}).second) {
        continue;
      }
      cached_modes_.push_back({mode.width, mode.height, mode.frame_rate});
    }
  }
  bool formatted = false;
  v4l2_format fmt = {};
  int stream_fps = frame_rate > 0 ? frame_rate : 30;
  if (!available.empty()) {
    const NativeMode pick =
        NearestMode(available, width, height, frame_rate);
    FacLog("StartCapture pick %dx%d@%d fourcc=%u modes=%zu", pick.width,
           pick.height, pick.frame_rate, pick.fourcc, available.size());
    if (TrySetFormat(pick.fourcc, pick.width, pick.height, &fmt) &&
        CanConvert(fmt.fmt.pix.pixelformat)) {
      formatted = true;
      pixelformat_ = fmt.fmt.pix.pixelformat;
      if (pick.frame_rate > 0) {
        stream_fps = pick.frame_rate;
      }
    }
  }
  const uint32_t candidates[] = {
      V4L2_PIX_FMT_YUYV, V4L2_PIX_FMT_NV12, V4L2_PIX_FMT_RGB24,
      V4L2_PIX_FMT_BGR24, V4L2_PIX_FMT_MJPEG, V4L2_PIX_FMT_JPEG};
  const int sizes[][2] = {{width, height}, {1280, 720}, {640, 480}, {0, 0}};
  if (!formatted) {
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
  }
  if (!formatted) {
    close(fd_);
    fd_ = -1;
    return false;
  }
  width_ = static_cast<int>(fmt.fmt.pix.width);
  height_ = static_cast<int>(fmt.fmt.pix.height);
  bytesperline_ = static_cast<int>(fmt.fmt.pix.bytesperline);
  frame_rate_ = stream_fps;
  v4l2_streamparm parm = {};
  parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (IoctlTimed(&fd_, VIDIOC_G_PARM, &parm, sizeof(parm), 250) == 0 &&
      (parm.parm.capture.capability & V4L2_CAP_TIMEPERFRAME)) {
    parm.parm.capture.timeperframe.numerator = 1;
    parm.parm.capture.timeperframe.denominator =
        static_cast<uint32_t>(stream_fps);
    IoctlTimed(&fd_, VIDIOC_S_PARM, &parm, sizeof(parm), 250);
    if (fd_ >= 0 && parm.parm.capture.timeperframe.numerator != 0) {
      frame_rate_ = static_cast<int>(
          parm.parm.capture.timeperframe.denominator /
          parm.parm.capture.timeperframe.numerator);
    }
  }
  if (fd_ < 0) {
    return false;
  }
  v4l2_requestbuffers req = {};
  req.count = 4;
  req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  req.memory = V4L2_MEMORY_MMAP;
  if (IoctlTimed(&fd_, VIDIOC_REQBUFS, &req, sizeof(req), 750) < 0 ||
      req.count < 2) {
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
    return false;
  }
  buffers_.resize(req.count);
  for (uint32_t i = 0; i < req.count; i++) {
    v4l2_buffer buf = {};
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    buf.index = i;
    if (IoctlTimed(&fd_, VIDIOC_QUERYBUF, &buf, sizeof(buf), 250) < 0) {
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
    if (IoctlTimed(&fd_, VIDIOC_QBUF, &buf, sizeof(buf), 250) < 0) {
      StopCapture();
      return false;
    }
  }
  v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (IoctlTimed(&fd_, VIDIOC_STREAMON, &type, sizeof(type), 750) < 0) {
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
  if (IoctlTimed(&fd_, VIDIOC_S_FMT, &fmt, sizeof(fmt), 750) < 0) {
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
      ConvertFrame(static_cast<const uint8_t*>(buffers_[buf.index].start),
                   buf.bytesused);
    }
    ioctl(fd_, VIDIOC_QBUF, &buf);
    // ConvertFrame writes decoded_. Process that buffer, then swap into
    // front_ so the next V4L2 convert cannot clobber pixels CopyPixels
    // has not consumed yet.
    if (!decoded_.empty() && !muted_.load() && enabled_.load()) {
      const int proc_w = width_;
      const int proc_h = height_;
      const size_t bytes =
          static_cast<size_t>(proc_w) * static_cast<size_t>(proc_h) * 4;
      if (decoded_.size() == bytes) {
        processor_.Process(decoded_.data(), proc_w, proc_h);
        std::lock_guard<std::mutex> lock(mutex_);
        if (muted_.load() || !enabled_.load()) {
          FillBlackLocked();
        } else if (width_ == proc_w && height_ == proc_h) {
          front_.swap(decoded_);
          if (front_.size() != bytes) {
            front_.assign(bytes, 0);
          }
        }
      }
    }
    RequestTextureMark();
  }
}

void CameraGraph::ConvertFrame(const uint8_t* src, size_t src_len) {
  std::lock_guard<std::mutex> lock(mutex_);
  const size_t bytes = static_cast<size_t>(width_) * height_ * 4;
  if (decoded_.size() != bytes) {
    decoded_.assign(bytes, 0);
  }
  uint8_t* dst = decoded_.data();
  const int stride = bytesperline_ > 0 ? bytesperline_ : width_ * 2;
  if (pixelformat_ == V4L2_PIX_FMT_MJPEG || pixelformat_ == V4L2_PIX_FMT_JPEG) {
    if (src != nullptr && src_len > 0) {
      const std::vector<uint8_t> jpeg = JpegWithDht(src, src_len);
      g_autoptr(GBytes) bytes = g_bytes_new(jpeg.data(), jpeg.size());
      g_autoptr(GMemoryInputStream) stream =
          G_MEMORY_INPUT_STREAM(g_memory_input_stream_new_from_bytes(bytes));
      g_autoptr(GError) error = nullptr;
      g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_stream(
          G_INPUT_STREAM(stream), nullptr, &error);
      if (pixbuf != nullptr) {
        const int pw = gdk_pixbuf_get_width(pixbuf);
        const int ph = gdk_pixbuf_get_height(pixbuf);
        const int channels = gdk_pixbuf_get_n_channels(pixbuf);
        const int row_stride = gdk_pixbuf_get_rowstride(pixbuf);
        const uint8_t* pixels = gdk_pixbuf_get_pixels(pixbuf);
        const int copy_w = std::min(width_, pw);
        const int copy_h = std::min(height_, ph);
        for (int y = 0; y < copy_h; y++) {
          const uint8_t* row =
              pixels + static_cast<ptrdiff_t>(row_stride) * y;
          uint8_t* out = dst + static_cast<size_t>(y) * width_ * 4;
          for (int x = 0; x < copy_w; x++) {
            out[x * 4 + 0] = row[x * channels + 0];
            out[x * 4 + 1] = row[x * channels + 1];
            out[x * 4 + 2] = row[x * channels + 2];
            out[x * 4 + 3] = 255;
          }
        }
      }
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
  for (size_t i = 0; i + 3 < decoded_.size(); i += 64) {
    if (decoded_[i] > 8 || decoded_[i + 1] > 8 || decoded_[i + 2] > 8) {
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
