#include "video_processor.h"

#include <dlfcn.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gio/gio.h>
#include <glib.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

#ifdef FAC_HAS_ONNXRUNTIME
#include "onnxruntime_c_api.h"
#endif

namespace {

#ifdef FAC_HAS_ONNXRUNTIME
constexpr int kModel = 256;
#endif

void FillOpaqueBlack(uint8_t* rgba, int width, int height) {
  const size_t n = static_cast<size_t>(width) * height * 4;
  for (size_t i = 0; i + 3 < n; i += 4) {
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 255;
  }
}

std::string ReadString(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return {};
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return {};
  }
  return fl_value_get_string(value);
}

int ReadInt(FlValue* args, const char* key, int fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return static_cast<int>(fl_value_get_int(value));
}

std::vector<uint8_t> ReadBytes(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return {};
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) {
    return {};
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_UINT8_LIST) {
    const size_t n = fl_value_get_length(value);
    const uint8_t* data = fl_value_get_uint8_list(value);
    return {data, data + n};
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_LIST) {
    const size_t n = fl_value_get_length(value);
    std::vector<uint8_t> out;
    out.reserve(n);
    for (size_t i = 0; i < n; i++) {
      FlValue* item = fl_value_get_list_value(value, i);
      if (item != nullptr && fl_value_get_type(item) == FL_VALUE_TYPE_INT) {
        out.push_back(static_cast<uint8_t>(fl_value_get_int(item)));
      }
    }
    return out;
  }
  return {};
}

std::string FileFromAsset(const std::string& asset) {
  std::string path = asset;
  if (path.rfind("file:///", 0) == 0) {
    path = path.substr(7);
  } else if (path.rfind("file://", 0) == 0) {
    path = path.substr(7);
  }
  return path;
}

bool FileReadable(const std::string& path) {
  return !path.empty() && access(path.c_str(), R_OK) == 0;
}

#ifdef FAC_HAS_ONNXRUNTIME
std::string DirOf(const char* path) {
  if (path == nullptr || path[0] == '\0') {
    return {};
  }
  std::string dir(path);
  const auto slash = dir.find_last_of('/');
  if (slash != std::string::npos) {
    dir.resize(slash + 1);
  }
  return dir;
}

std::string ModelPath() {
  const std::string name = "selfie_segmentation.onnx";
  Dl_info info{};
  if (dladdr(reinterpret_cast<void*>(&ModelPath), &info) &&
      info.dli_fname != nullptr) {
    const std::string next_to_so = DirOf(info.dli_fname) + name;
    if (FileReadable(next_to_so)) {
      return next_to_so;
    }
  }
  return name;
}
#endif

float Clamp01(float value) {
  if (value < 0.f) {
    return 0.f;
  }
  if (value > 1.f) {
    return 1.f;
  }
  return value;
}

int ClampIndex(int value, int max_inclusive) {
  if (value < 0) {
    return 0;
  }
  if (value > max_inclusive) {
    return max_inclusive;
  }
  return value;
}

void ScaleRgba(const uint8_t* src, int src_w, int src_h, uint8_t* dst, int dst_w,
               int dst_h) {
  if (src_w <= 0 || src_h <= 0 || dst_w <= 0 || dst_h <= 0) {
    return;
  }
  if (src_w == dst_w && src_h == dst_h) {
    std::memcpy(dst, src, static_cast<size_t>(dst_w) * dst_h * 4);
    return;
  }
  for (int y = 0; y < dst_h; y++) {
    const float fy = (static_cast<float>(y) + 0.5f) * src_h / dst_h - 0.5f;
    const int y0 = ClampIndex(static_cast<int>(std::floor(fy)), src_h - 1);
    const int y1 = ClampIndex(y0 + 1, src_h - 1);
    const float ty = Clamp01(fy - static_cast<float>(y0));
    for (int x = 0; x < dst_w; x++) {
      const float fx = (static_cast<float>(x) + 0.5f) * src_w / dst_w - 0.5f;
      const int x0 = ClampIndex(static_cast<int>(std::floor(fx)), src_w - 1);
      const int x1 = ClampIndex(x0 + 1, src_w - 1);
      const float tx = Clamp01(fx - static_cast<float>(x0));
      uint8_t* out = dst + (static_cast<size_t>(y) * dst_w + x) * 4;
      for (int c = 0; c < 4; c++) {
        const float p00 =
            src[(static_cast<size_t>(y0) * src_w + x0) * 4 + c];
        const float p10 =
            src[(static_cast<size_t>(y0) * src_w + x1) * 4 + c];
        const float p01 =
            src[(static_cast<size_t>(y1) * src_w + x0) * 4 + c];
        const float p11 =
            src[(static_cast<size_t>(y1) * src_w + x1) * 4 + c];
        const float top = p00 + (p10 - p00) * tx;
        const float bot = p01 + (p11 - p01) * tx;
        out[c] = static_cast<uint8_t>(top + (bot - top) * ty + 0.5f);
      }
    }
  }
}

void CoverStill(const uint8_t* src, int src_w, int src_h, uint8_t* dst,
                int dst_w, int dst_h) {
  if (src_w <= 0 || src_h <= 0 || dst_w <= 0 || dst_h <= 0) {
    return;
  }
  const float scale =
      std::max(static_cast<float>(dst_w) / src_w,
               static_cast<float>(dst_h) / src_h);
  const float src_cover_w = dst_w / scale;
  const float src_cover_h = dst_h / scale;
  const float ox = (src_w - src_cover_w) * 0.5f;
  const float oy = (src_h - src_cover_h) * 0.5f;
  for (int y = 0; y < dst_h; y++) {
    const float fy = oy + (static_cast<float>(y) + 0.5f) * src_cover_h / dst_h -
                     0.5f;
    const int y0 = ClampIndex(static_cast<int>(std::floor(fy)), src_h - 1);
    const int y1 = ClampIndex(y0 + 1, src_h - 1);
    const float ty = Clamp01(fy - static_cast<float>(y0));
    for (int x = 0; x < dst_w; x++) {
      const float fx =
          ox + (static_cast<float>(x) + 0.5f) * src_cover_w / dst_w - 0.5f;
      const int x0 = ClampIndex(static_cast<int>(std::floor(fx)), src_w - 1);
      const int x1 = ClampIndex(x0 + 1, src_w - 1);
      const float tx = Clamp01(fx - static_cast<float>(x0));
      uint8_t* out = dst + (static_cast<size_t>(y) * dst_w + x) * 4;
      for (int c = 0; c < 4; c++) {
        const float p00 =
            src[(static_cast<size_t>(y0) * src_w + x0) * 4 + c];
        const float p10 =
            src[(static_cast<size_t>(y0) * src_w + x1) * 4 + c];
        const float p01 =
            src[(static_cast<size_t>(y1) * src_w + x0) * 4 + c];
        const float p11 =
            src[(static_cast<size_t>(y1) * src_w + x1) * 4 + c];
        const float top = p00 + (p10 - p00) * tx;
        const float bot = p01 + (p11 - p01) * tx;
        out[c] = static_cast<uint8_t>(top + (bot - top) * ty + 0.5f);
      }
      out[3] = 255;
    }
  }
}

void BoxBlurRgba(uint8_t* img, int w, int h, int radius,
                 std::vector<uint8_t>* tmp) {
  if (radius <= 0 || w <= 0 || h <= 0) {
    return;
  }
  tmp->assign(static_cast<size_t>(w) * h * 4, 0);
  const int window = radius * 2 + 1;
  for (int y = 0; y < h; y++) {
    int sum[3] = {0, 0, 0};
    for (int x = -radius; x <= radius; x++) {
      const uint8_t* px =
          img + (static_cast<size_t>(y) * w + ClampIndex(x, w - 1)) * 4;
      sum[0] += px[0];
      sum[1] += px[1];
      sum[2] += px[2];
    }
    for (int x = 0; x < w; x++) {
      uint8_t* out = tmp->data() + (static_cast<size_t>(y) * w + x) * 4;
      out[0] = static_cast<uint8_t>(sum[0] / window);
      out[1] = static_cast<uint8_t>(sum[1] / window);
      out[2] = static_cast<uint8_t>(sum[2] / window);
      out[3] = 255;
      const uint8_t* leave =
          img + (static_cast<size_t>(y) * w + ClampIndex(x - radius, w - 1)) * 4;
      const uint8_t* enter =
          img +
          (static_cast<size_t>(y) * w + ClampIndex(x + radius + 1, w - 1)) * 4;
      sum[0] += enter[0] - leave[0];
      sum[1] += enter[1] - leave[1];
      sum[2] += enter[2] - leave[2];
    }
  }
  for (int x = 0; x < w; x++) {
    int sum[3] = {0, 0, 0};
    for (int y = -radius; y <= radius; y++) {
      const uint8_t* px =
          tmp->data() +
          (static_cast<size_t>(ClampIndex(y, h - 1)) * w + x) * 4;
      sum[0] += px[0];
      sum[1] += px[1];
      sum[2] += px[2];
    }
    for (int y = 0; y < h; y++) {
      uint8_t* out = img + (static_cast<size_t>(y) * w + x) * 4;
      out[0] = static_cast<uint8_t>(sum[0] / window);
      out[1] = static_cast<uint8_t>(sum[1] / window);
      out[2] = static_cast<uint8_t>(sum[2] / window);
      out[3] = 255;
      const uint8_t* leave =
          tmp->data() +
          (static_cast<size_t>(ClampIndex(y - radius, h - 1)) * w + x) * 4;
      const uint8_t* enter =
          tmp->data() +
          (static_cast<size_t>(ClampIndex(y + radius + 1, h - 1)) * w + x) * 4;
      sum[0] += enter[0] - leave[0];
      sum[1] += enter[1] - leave[1];
      sum[2] += enter[2] - leave[2];
    }
  }
}

#ifdef FAC_HAS_ONNXRUNTIME
void DilateGray(uint8_t* img, int w, int h, int radius,
                std::vector<uint8_t>* tmp) {
  if (radius <= 0 || w <= 0 || h <= 0) {
    return;
  }
  tmp->assign(static_cast<size_t>(w) * h, 0);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      uint8_t m = 0;
      for (int dy = -radius; dy <= radius; dy++) {
        const int yy = ClampIndex(y + dy, h - 1);
        for (int dx = -radius; dx <= radius; dx++) {
          const int xx = ClampIndex(x + dx, w - 1);
          const uint8_t v = img[static_cast<size_t>(yy) * w + xx];
          if (v > m) {
            m = v;
          }
        }
      }
      (*tmp)[static_cast<size_t>(y) * w + x] = m;
    }
  }
  std::memcpy(img, tmp->data(), tmp->size());
}

void ErodeGray(uint8_t* img, int w, int h, int radius,
               std::vector<uint8_t>* tmp) {
  if (radius <= 0 || w <= 0 || h <= 0) {
    return;
  }
  tmp->assign(static_cast<size_t>(w) * h, 0);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      uint8_t m = 255;
      for (int dy = -radius; dy <= radius; dy++) {
        const int yy = ClampIndex(y + dy, h - 1);
        for (int dx = -radius; dx <= radius; dx++) {
          const int xx = ClampIndex(x + dx, w - 1);
          const uint8_t v = img[static_cast<size_t>(yy) * w + xx];
          if (v < m) {
            m = v;
          }
        }
      }
      (*tmp)[static_cast<size_t>(y) * w + x] = m;
    }
  }
  std::memcpy(img, tmp->data(), tmp->size());
}

void BoxBlurGray(uint8_t* img, int w, int h, int radius,
                 std::vector<uint8_t>* tmp) {
  if (radius <= 0 || w <= 0 || h <= 0) {
    return;
  }
  tmp->assign(static_cast<size_t>(w) * h, 0);
  const int window = radius * 2 + 1;
  for (int y = 0; y < h; y++) {
    int sum = 0;
    for (int x = -radius; x <= radius; x++) {
      sum += img[static_cast<size_t>(y) * w + ClampIndex(x, w - 1)];
    }
    for (int x = 0; x < w; x++) {
      (*tmp)[static_cast<size_t>(y) * w + x] =
          static_cast<uint8_t>(sum / window);
      const int leave = ClampIndex(x - radius, w - 1);
      const int enter = ClampIndex(x + radius + 1, w - 1);
      sum += img[static_cast<size_t>(y) * w + enter] -
             img[static_cast<size_t>(y) * w + leave];
    }
  }
  for (int x = 0; x < w; x++) {
    int sum = 0;
    for (int y = -radius; y <= radius; y++) {
      sum += (*tmp)[static_cast<size_t>(ClampIndex(y, h - 1)) * w + x];
    }
    for (int y = 0; y < h; y++) {
      img[static_cast<size_t>(y) * w + x] =
          static_cast<uint8_t>(sum / window);
      const int leave = ClampIndex(y - radius, h - 1);
      const int enter = ClampIndex(y + radius + 1, h - 1);
      sum += (*tmp)[static_cast<size_t>(enter) * w + x] -
             (*tmp)[static_cast<size_t>(leave) * w + x];
    }
  }
}

// Stretching 16:9 into 256x256 zeros MediaPipe alphas. Fit and pad instead.
void LetterboxRgb(const uint8_t* rgba, int width, int height, float* input) {
  const float scale = std::min(static_cast<float>(kModel) / width,
                               static_cast<float>(kModel) / height);
  const float pad_x =
      (kModel - static_cast<float>(width) * scale) * 0.5f;
  const float pad_y =
      (kModel - static_cast<float>(height) * scale) * 0.5f;
  const size_t plane = static_cast<size_t>(kModel) * kModel;
  std::fill(input, input + plane * 3, 0.f);
  for (int y = 0; y < kModel; y++) {
    for (int x = 0; x < kModel; x++) {
      const float ix = (static_cast<float>(x) - pad_x + 0.5f) / scale - 0.5f;
      const float iy = (static_cast<float>(y) - pad_y + 0.5f) / scale - 0.5f;
      if (ix < 0.f || iy < 0.f || ix > static_cast<float>(width - 1) ||
          iy > static_cast<float>(height - 1)) {
        continue;
      }
      const int x0 = ClampIndex(static_cast<int>(std::floor(ix)), width - 1);
      const int y0 = ClampIndex(static_cast<int>(std::floor(iy)), height - 1);
      const int x1 = ClampIndex(x0 + 1, width - 1);
      const int y1 = ClampIndex(y0 + 1, height - 1);
      const float tx = Clamp01(ix - static_cast<float>(x0));
      const float ty = Clamp01(iy - static_cast<float>(y0));
      const size_t i00 = (static_cast<size_t>(y0) * width + x0) * 4;
      const size_t i10 = (static_cast<size_t>(y0) * width + x1) * 4;
      const size_t i01 = (static_cast<size_t>(y1) * width + x0) * 4;
      const size_t i11 = (static_cast<size_t>(y1) * width + x1) * 4;
      const size_t idx = static_cast<size_t>(y) * kModel + x;
      for (int c = 0; c < 3; c++) {
        const float p00 = rgba[i00 + c];
        const float p10 = rgba[i10 + c];
        const float p01 = rgba[i01 + c];
        const float p11 = rgba[i11 + c];
        const float top = p00 + (p10 - p00) * tx;
        const float bot = p01 + (p11 - p01) * tx;
        input[c * plane + idx] = (top + (bot - top) * ty) * (1.f / 255.f);
      }
    }
  }
}

void UnletterboxMask(const uint8_t* src, uint8_t* dst, int dst_w, int dst_h) {
  const float scale = std::min(static_cast<float>(kModel) / dst_w,
                               static_cast<float>(kModel) / dst_h);
  const float pad_x =
      (kModel - static_cast<float>(dst_w) * scale) * 0.5f;
  const float pad_y =
      (kModel - static_cast<float>(dst_h) * scale) * 0.5f;
  for (int y = 0; y < dst_h; y++) {
    for (int x = 0; x < dst_w; x++) {
      const float mx = pad_x + (static_cast<float>(x) + 0.5f) * scale - 0.5f;
      const float my = pad_y + (static_cast<float>(y) + 0.5f) * scale - 0.5f;
      const int ix = ClampIndex(static_cast<int>(mx + 0.5f), kModel - 1);
      const int iy = ClampIndex(static_cast<int>(my + 0.5f), kModel - 1);
      dst[static_cast<size_t>(y) * dst_w + x] =
          src[static_cast<size_t>(iy) * kModel + ix];
    }
  }
}
#endif

bool PixbufToRgba(GdkPixbuf* pixbuf, std::vector<uint8_t>* rgba, int* width,
                  int* height) {
  if (pixbuf == nullptr || rgba == nullptr) {
    return false;
  }
  const int w = gdk_pixbuf_get_width(pixbuf);
  const int h = gdk_pixbuf_get_height(pixbuf);
  const int channels = gdk_pixbuf_get_n_channels(pixbuf);
  const int stride = gdk_pixbuf_get_rowstride(pixbuf);
  const uint8_t* src = gdk_pixbuf_get_pixels(pixbuf);
  if (w <= 0 || h <= 0 || src == nullptr || channels < 3) {
    return false;
  }
  rgba->assign(static_cast<size_t>(w) * h * 4, 255);
  for (int y = 0; y < h; y++) {
    const uint8_t* row = src + static_cast<ptrdiff_t>(stride) * y;
    uint8_t* out = rgba->data() + static_cast<size_t>(y) * w * 4;
    for (int x = 0; x < w; x++) {
      out[x * 4 + 0] = row[x * channels + 0];
      out[x * 4 + 1] = row[x * channels + 1];
      out[x * 4 + 2] = row[x * channels + 2];
      out[x * 4 + 3] = channels >= 4 ? row[x * channels + 3] : 255;
    }
  }
  *width = w;
  *height = h;
  return true;
}

bool DecodeStillBytes(const std::vector<uint8_t>& bytes,
                      std::vector<uint8_t>* rgba, int* width, int* height) {
  if (bytes.empty()) {
    return false;
  }
  g_autoptr(GMemoryInputStream) stream = G_MEMORY_INPUT_STREAM(
      g_memory_input_stream_new_from_data(bytes.data(), bytes.size(), nullptr));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_stream(
      G_INPUT_STREAM(stream), nullptr, &error);
  return PixbufToRgba(pixbuf, rgba, width, height);
}

bool DecodeStillFile(const std::string& path, std::vector<uint8_t>* rgba,
                     int* width, int* height) {
  if (!FileReadable(path)) {
    return false;
  }
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf =
      gdk_pixbuf_new_from_file(path.c_str(), &error);
  return PixbufToRgba(pixbuf, rgba, width, height);
}

}  // namespace

struct PersonBackgroundProcessor::Impl {
  enum class Kind { None, Blur, Replace };

  std::mutex mutex_;
  Kind kind_ = Kind::None;
  int intensity_ = 50;
  std::vector<uint8_t> still_rgba_;
  int still_w_ = 0;
  int still_h_ = 0;
  std::atomic<int> consecutive_failures_{0};
  std::function<void()> on_unavailable_;
  static constexpr int kFailureLimit = 5;

  std::mutex session_mutex_;
  bool load_failed_ = false;
#ifdef FAC_HAS_ONNXRUNTIME
  const OrtApi* api_ = nullptr;
  OrtEnv* env_ = nullptr;
  OrtSessionOptions* options_ = nullptr;
  OrtSession* session_ = nullptr;
  OrtMemoryInfo* memory_info_ = nullptr;
#endif
  std::vector<float> input_;
  std::vector<uint8_t> mask256_;
  std::vector<uint8_t> mask256_prev_;
  std::vector<uint8_t> mask_;
  std::vector<uint8_t> mask_tmp_;
  std::vector<uint8_t> background_;
  std::vector<uint8_t> scratch_;
  std::vector<uint8_t> blur_tmp_;
  int last_w_ = 0;
  int last_h_ = 0;
  std::mutex work_mutex_;
  std::condition_variable cv_;
  std::thread worker_;
  std::atomic<bool> stop_{false};
  std::atomic<bool> segment_pending_{false};
  std::atomic<uint64_t> generation_{0};
  std::vector<uint8_t> segment_rgba_;
  int segment_w_ = 0;
  int segment_h_ = 0;
  std::vector<uint8_t> live_mask_;
  int live_w_ = 0;
  int live_h_ = 0;

  ~Impl() {
#ifdef FAC_HAS_ONNXRUNTIME
    {
      std::lock_guard<std::mutex> lock(work_mutex_);
      stop_.store(true);
    }
    cv_.notify_all();
    if (worker_.joinable()) {
      worker_.join();
    }
    if (api_ != nullptr) {
      if (session_ != nullptr) {
        api_->ReleaseSession(session_);
      }
      if (options_ != nullptr) {
        api_->ReleaseSessionOptions(options_);
      }
      if (memory_info_ != nullptr) {
        api_->ReleaseMemoryInfo(memory_info_);
      }
      if (env_ != nullptr) {
        api_->ReleaseEnv(env_);
      }
    }
#endif
  }

  bool EnsureSession() {
#ifdef FAC_HAS_ONNXRUNTIME
    std::lock_guard<std::mutex> lock(session_mutex_);
    if (session_ != nullptr) {
      StartWorker();
      return true;
    }
    if (load_failed_) {
      return false;
    }
    const OrtApiBase* base = OrtGetApiBase();
    if (base == nullptr) {
      load_failed_ = true;
      return false;
    }
    api_ = base->GetApi(ORT_API_VERSION);
    if (api_ == nullptr) {
      load_failed_ = true;
      return false;
    }
    const std::string path = ModelPath();
    if (!FileReadable(path)) {
      load_failed_ = true;
      return false;
    }
    OrtStatus* status = api_->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "fac", &env_);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      load_failed_ = true;
      return false;
    }
    status = api_->CreateSessionOptions(&options_);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      load_failed_ = true;
      return false;
    }
    status = api_->SetIntraOpNumThreads(options_, 1);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
    }
    status = api_->SetInterOpNumThreads(options_, 1);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
    }
    status = api_->CreateSession(env_, path.c_str(), options_, &session_);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      load_failed_ = true;
      return false;
    }
    status = api_->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault,
                                       &memory_info_);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      load_failed_ = true;
      return false;
    }
    input_.assign(static_cast<size_t>(3) * kModel * kModel, 0.f);
    mask256_.assign(static_cast<size_t>(kModel) * kModel, 0);
    mask256_prev_.clear();
    last_w_ = 0;
    last_h_ = 0;
    StartWorker();
    return true;
#else
    return false;
#endif
  }

  bool Segment(const uint8_t* rgba, int width, int height) {
#ifdef FAC_HAS_ONNXRUNTIME
    if (!EnsureSession() || rgba == nullptr || width <= 0 || height <= 0 ||
        api_ == nullptr || session_ == nullptr || memory_info_ == nullptr) {
      return false;
    }
    LetterboxRgb(rgba, width, height, input_.data());
    const int64_t shape[4] = {1, 3, kModel, kModel};
    OrtValue* input_tensor = nullptr;
    OrtStatus* status = api_->CreateTensorWithDataAsOrtValue(
        memory_info_, input_.data(), input_.size() * sizeof(float), shape, 4,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      return false;
    }
    const char* input_names[] = {"pixel_values"};
    const char* output_names[] = {"alphas"};
    OrtValue* output_tensor = nullptr;
    status = api_->Run(session_, nullptr, input_names,
                       const_cast<const OrtValue* const*>(&input_tensor), 1,
                       output_names, 1, &output_tensor);
    api_->ReleaseValue(input_tensor);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      return false;
    }
    float* out = nullptr;
    status = api_->GetTensorMutableData(output_tensor, reinterpret_cast<void**>(&out));
    if (status != nullptr || out == nullptr) {
      if (status != nullptr) {
        api_->ReleaseStatus(status);
      }
      api_->ReleaseValue(output_tensor);
      return false;
    }
    for (int i = 0; i < kModel * kModel; i++) {
      mask256_[static_cast<size_t>(i)] =
          static_cast<uint8_t>(Clamp01(out[i]) * 255.f + 0.5f);
    }
    api_->ReleaseValue(output_tensor);
    last_w_ = width;
    last_h_ = height;
    // Halfway between net-shrink (too tight) and expand-2 (halo).
    for (uint8_t& v : mask256_) {
      const float a = std::pow(v / 255.f, 2.4f);
      const float t = Clamp01((a - 0.35f) / 0.30f);
      const float s = t * t * (3.f - 2.f * t);
      v = static_cast<uint8_t>(s * 255.f + 0.5f);
    }
    ErodeGray(mask256_.data(), kModel, kModel, 1, &mask_tmp_);
    DilateGray(mask256_.data(), kModel, kModel, 1, &mask_tmp_);
    mask_.assign(static_cast<size_t>(width) * height, 0);
    UnletterboxMask(mask256_.data(), mask_.data(), width, height);
    BoxBlurGray(mask_.data(), width, height, 1, &mask_tmp_);
    return true;
#else
    (void)rgba;
    (void)width;
    (void)height;
    return false;
#endif
  }

  void BlurBackground(const uint8_t* rgba, int width, int height,
                      int intensity) {
    const size_t bytes = static_cast<size_t>(width) * height * 4;
    background_.assign(bytes, 0);
    if (intensity <= 0) {
      std::memcpy(background_.data(), rgba, bytes);
      return;
    }
    const float t = intensity / 100.f;
    const float factor = 0.16f - t * 0.10f;
    const int small_w =
        std::max(12, static_cast<int>(width * factor + 0.5f));
    const int small_h =
        std::max(12, static_cast<int>(height * factor + 0.5f));
    scratch_.assign(static_cast<size_t>(small_w) * small_h * 4, 0);
    ScaleRgba(rgba, width, height, scratch_.data(), small_w, small_h);
    const int passes = t >= 0.75f ? 3 : 2;
    const int radius = t >= 0.75f ? 3 : 2;
    for (int i = 0; i < passes; i++) {
      BoxBlurRgba(scratch_.data(), small_w, small_h, radius, &blur_tmp_);
    }
    ScaleRgba(scratch_.data(), small_w, small_h, background_.data(), width,
              height);
  }

  void Composite(uint8_t* rgba, int width, int height, const uint8_t* mask) {
    const size_t pixels = static_cast<size_t>(width) * height;
    if (background_.size() < pixels * 4 || mask == nullptr) {
      return;
    }
    for (size_t i = 0; i < pixels; i++) {
      const float a = mask[i] / 255.f;
      uint8_t* px = rgba + i * 4;
      const uint8_t* bg = background_.data() + i * 4;
      px[0] = static_cast<uint8_t>(bg[0] * (1.f - a) + px[0] * a + 0.5f);
      px[1] = static_cast<uint8_t>(bg[1] * (1.f - a) + px[1] * a + 0.5f);
      px[2] = static_cast<uint8_t>(bg[2] * (1.f - a) + px[2] * a + 0.5f);
      px[3] = 255;
    }
  }

  void StartWorker() {
#ifdef FAC_HAS_ONNXRUNTIME
    if (worker_.joinable()) {
      return;
    }
    stop_.store(false);
    worker_ = std::thread([this] { WorkerLoop(); });
#endif
  }

  void WorkerLoop() {
#ifdef FAC_HAS_ONNXRUNTIME
    while (!stop_.load()) {
      std::vector<uint8_t> rgba;
      int width = 0;
      int height = 0;
      uint64_t gen = 0;
      {
        std::unique_lock<std::mutex> lock(work_mutex_);
        cv_.wait(lock, [this] {
          return stop_.load() || segment_pending_.load();
        });
        if (stop_.load()) {
          break;
        }
        rgba = std::move(segment_rgba_);
        width = segment_w_;
        height = segment_h_;
        gen = generation_.load();
        segment_pending_.store(false);
      }
      if (rgba.empty() || width <= 0 || height <= 0) {
        continue;
      }
      if (!Segment(rgba.data(), width, height)) {
        std::function<void()> callback;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          if (generation_.load() != gen) {
            continue;
          }
          const int failures = consecutive_failures_.fetch_add(1) + 1;
          if (failures < kFailureLimit) {
            continue;
          }
          if (kind_ == Kind::None) {
            consecutive_failures_.store(0);
            continue;
          }
          kind_ = Kind::None;
          still_rgba_.clear();
          still_w_ = 0;
          still_h_ = 0;
          live_mask_.clear();
          live_w_ = 0;
          live_h_ = 0;
          consecutive_failures_.store(0);
          callback = on_unavailable_;
        }
        if (callback) {
          auto* fn = new std::function<void()>(std::move(callback));
          g_idle_add(
              [](gpointer data) -> gboolean {
                auto* f = static_cast<std::function<void()>*>(data);
                (*f)();
                delete f;
                return G_SOURCE_REMOVE;
              },
              fn);
        }
        continue;
      }
      consecutive_failures_.store(0);
      std::lock_guard<std::mutex> lock(mutex_);
      if (generation_.load() != gen || kind_ == Kind::None) {
        continue;
      }
      live_mask_.swap(mask_);
      live_w_ = width;
      live_h_ = height;
    }
#endif
  }
};

PersonBackgroundProcessor::PersonBackgroundProcessor()
    : impl_(std::make_unique<Impl>()) {}

PersonBackgroundProcessor::~PersonBackgroundProcessor() = default;

void PersonBackgroundProcessor::SetOnUnavailable(std::function<void()> callback) {
  std::lock_guard<std::mutex> lock(impl_->mutex_);
  impl_->on_unavailable_ = std::move(callback);
}

std::string PersonBackgroundProcessor::Apply(FlValue* args) {
  const std::string kind = ReadString(args, "kind");
  if (kind.empty() || kind == "none") {
    std::lock_guard<std::mutex> lock(impl_->mutex_);
    impl_->kind_ = Impl::Kind::None;
    impl_->still_rgba_.clear();
    impl_->still_w_ = 0;
    impl_->still_h_ = 0;
    impl_->live_mask_.clear();
    impl_->live_w_ = 0;
    impl_->live_h_ = 0;
    impl_->consecutive_failures_.store(0);
    impl_->generation_.fetch_add(1);
    return "ready";
  }
  if (kind == "blur") {
    const int intensity = ReadInt(args, "intensity", 50);
    if (intensity < 0 || intensity > 100) {
      return "invalid";
    }
    if (!impl_->EnsureSession()) {
      return "unavailable";
    }
    std::lock_guard<std::mutex> lock(impl_->mutex_);
    impl_->kind_ = Impl::Kind::Blur;
    impl_->intensity_ = intensity;
    impl_->consecutive_failures_.store(0);
    return "ready";
  }
  if (kind == "replace") {
    std::vector<uint8_t> still;
    int still_w = 0;
    int still_h = 0;
    const std::vector<uint8_t> bytes = ReadBytes(args, "bytes");
    bool decoded = false;
    if (!bytes.empty()) {
      decoded = DecodeStillBytes(bytes, &still, &still_w, &still_h);
    }
    if (!decoded) {
      decoded =
          DecodeStillFile(FileFromAsset(ReadString(args, "asset")), &still,
                          &still_w, &still_h);
    }
    if (!decoded) {
      return "invalid";
    }
    if (!impl_->EnsureSession()) {
      return "unavailable";
    }
    std::lock_guard<std::mutex> lock(impl_->mutex_);
    impl_->kind_ = Impl::Kind::Replace;
    impl_->still_rgba_ = std::move(still);
    impl_->still_w_ = still_w;
    impl_->still_h_ = still_h;
    impl_->consecutive_failures_.store(0);
    return "ready";
  }
  return "unavailable";
}

void PersonBackgroundProcessor::Process(uint8_t* rgba, int width, int height) {
  if (rgba == nullptr || width <= 0 || height <= 0) {
    return;
  }
  Impl::Kind kind;
  int intensity;
  std::vector<uint8_t> still;
  int still_w = 0;
  int still_h = 0;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex_);
    kind = impl_->kind_;
    intensity = impl_->intensity_;
    if (kind == Impl::Kind::None) {
      return;
    }
    if (kind == Impl::Kind::Replace) {
      still = impl_->still_rgba_;
      still_w = impl_->still_w_;
      still_h = impl_->still_h_;
    }
  }
  if (!impl_->EnsureSession()) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(impl_->work_mutex_);
    if (!impl_->segment_pending_.load()) {
      impl_->segment_rgba_.assign(
          rgba, rgba + static_cast<size_t>(width) * height * 4);
      impl_->segment_w_ = width;
      impl_->segment_h_ = height;
      impl_->segment_pending_.store(true);
      impl_->cv_.notify_one();
    }
  }
  const size_t pixels = static_cast<size_t>(width) * height;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex_);
    if (impl_->live_w_ != width || impl_->live_h_ != height ||
        impl_->live_mask_.size() != pixels) {
      FillOpaqueBlack(rgba, width, height);
      return;
    }
  }
  if (kind == Impl::Kind::Blur) {
    impl_->BlurBackground(rgba, width, height, intensity);
  } else {
    if (still.empty() || still_w <= 0 || still_h <= 0) {
      return;
    }
    impl_->background_.assign(pixels * 4, 0);
    CoverStill(still.data(), still_w, still_h, impl_->background_.data(), width,
               height);
  }
  std::lock_guard<std::mutex> lock(impl_->mutex_);
  if (impl_->live_w_ == width && impl_->live_h_ == height &&
      impl_->live_mask_.size() == pixels) {
    impl_->Composite(rgba, width, height, impl_->live_mask_.data());
  }
}
