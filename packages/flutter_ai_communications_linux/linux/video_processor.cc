#include "video_processor.h"

#include <dlfcn.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gio/gio.h>
#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <vector>

#ifdef FAC_HAS_ONNXRUNTIME
#include "onnxruntime_c_api.h"
#endif

namespace {

#ifdef FAC_HAS_ONNXRUNTIME
constexpr int kModel = 256;
#endif

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

#ifdef FAC_HAS_ONNXRUNTIME
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

#ifdef FAC_HAS_ONNXRUNTIME
void ScaleMask(const uint8_t* src, int src_w, int src_h, uint8_t* dst, int dst_w,
               int dst_h) {
  if (src_w <= 0 || src_h <= 0 || dst_w <= 0 || dst_h <= 0) {
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
      const float p00 = src[static_cast<size_t>(y0) * src_w + x0];
      const float p10 = src[static_cast<size_t>(y0) * src_w + x1];
      const float p01 = src[static_cast<size_t>(y1) * src_w + x0];
      const float p11 = src[static_cast<size_t>(y1) * src_w + x1];
      const float top = p00 + (p10 - p00) * tx;
      const float bot = p01 + (p11 - p01) * tx;
      dst[static_cast<size_t>(y) * dst_w + x] =
          static_cast<uint8_t>(top + (bot - top) * ty + 0.5f);
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
  std::vector<uint8_t> mask_;
  std::vector<uint8_t> background_;
  std::vector<uint8_t> scratch_;

  ~Impl() {
#ifdef FAC_HAS_ONNXRUNTIME
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
    for (int y = 0; y < kModel; y++) {
      const float fy =
          (static_cast<float>(y) + 0.5f) * height / kModel - 0.5f;
      const int y0 = ClampIndex(static_cast<int>(std::floor(fy)), height - 1);
      const int y1 = ClampIndex(y0 + 1, height - 1);
      const float ty = Clamp01(fy - static_cast<float>(y0));
      for (int x = 0; x < kModel; x++) {
        const float fx =
            (static_cast<float>(x) + 0.5f) * width / kModel - 0.5f;
        const int x0 = ClampIndex(static_cast<int>(std::floor(fx)), width - 1);
        const int x1 = ClampIndex(x0 + 1, width - 1);
        const float tx = Clamp01(fx - static_cast<float>(x0));
        const size_t i00 = (static_cast<size_t>(y0) * width + x0) * 4;
        const size_t i10 = (static_cast<size_t>(y0) * width + x1) * 4;
        const size_t i01 = (static_cast<size_t>(y1) * width + x0) * 4;
        const size_t i11 = (static_cast<size_t>(y1) * width + x1) * 4;
        const size_t plane = static_cast<size_t>(kModel) * kModel;
        const size_t idx = static_cast<size_t>(y) * kModel + x;
        for (int c = 0; c < 3; c++) {
          const float p00 = rgba[i00 + c];
          const float p10 = rgba[i10 + c];
          const float p01 = rgba[i01 + c];
          const float p11 = rgba[i11 + c];
          const float top = p00 + (p10 - p00) * tx;
          const float bot = p01 + (p11 - p01) * tx;
          input_[c * plane + idx] =
              (top + (bot - top) * ty) * (1.f / 255.f);
        }
      }
    }
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
    mask_.assign(static_cast<size_t>(width) * height, 0);
    ScaleMask(mask256_.data(), kModel, kModel, mask_.data(), width, height);
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
    const float factor = std::pow(1.f - t, 1.5f) * 0.88f + 0.12f;
    const int small_w = std::max(8, static_cast<int>(width * factor));
    const int small_h = std::max(8, static_cast<int>(height * factor));
    scratch_.assign(static_cast<size_t>(small_w) * small_h * 4, 0);
    ScaleRgba(rgba, width, height, scratch_.data(), small_w, small_h);
    ScaleRgba(scratch_.data(), small_w, small_h, background_.data(), width,
              height);
  }

  void Composite(uint8_t* rgba, int width, int height) {
    const size_t pixels = static_cast<size_t>(width) * height;
    if (background_.size() < pixels * 4 || mask_.size() < pixels) {
      return;
    }
    for (size_t i = 0; i < pixels; i++) {
      const float a = mask_[i] / 255.f;
      uint8_t* px = rgba + i * 4;
      const uint8_t* bg = background_.data() + i * 4;
      px[0] = static_cast<uint8_t>(bg[0] * (1.f - a) + px[0] * a + 0.5f);
      px[1] = static_cast<uint8_t>(bg[1] * (1.f - a) + px[1] * a + 0.5f);
      px[2] = static_cast<uint8_t>(bg[2] * (1.f - a) + px[2] * a + 0.5f);
      px[3] = 255;
    }
  }
};

PersonBackgroundProcessor::PersonBackgroundProcessor()
    : impl_(std::make_unique<Impl>()) {}

PersonBackgroundProcessor::~PersonBackgroundProcessor() = default;

std::string PersonBackgroundProcessor::Apply(FlValue* args) {
  const std::string kind = ReadString(args, "kind");
  if (kind.empty() || kind == "none") {
    std::lock_guard<std::mutex> lock(impl_->mutex_);
    impl_->kind_ = Impl::Kind::None;
    impl_->still_rgba_.clear();
    impl_->still_w_ = 0;
    impl_->still_h_ = 0;
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
  if (!impl_->Segment(rgba, width, height)) {
    return;
  }
  if (kind == Impl::Kind::Blur) {
    impl_->BlurBackground(rgba, width, height, intensity);
  } else {
    if (still.empty() || still_w <= 0 || still_h <= 0) {
      return;
    }
    impl_->background_.assign(static_cast<size_t>(width) * height * 4, 0);
    CoverStill(still.data(), still_w, still_h, impl_->background_.data(), width,
               height);
  }
  impl_->Composite(rgba, width, height);
}
