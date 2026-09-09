#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "video_processor.h"

#include <windows.h>
#include <unknwn.h>
#include <wincodec.h>
#include <winrt/Windows.AI.MachineLearning.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
using winrt::Windows::AI::MachineLearning::LearningModel;
using winrt::Windows::AI::MachineLearning::LearningModelBinding;
using winrt::Windows::AI::MachineLearning::LearningModelSession;
using winrt::Windows::AI::MachineLearning::TensorFloat;

namespace {

constexpr int kModel = 256;

std::string ReadString(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return {};
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return {};
}

int ReadInt(const flutter::EncodableMap& args, const char* key, int fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return *i32;
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*i64);
  }
  return fallback;
}

std::vector<uint8_t> ReadBytes(const flutter::EncodableMap& args,
                               const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return {};
  }
  if (const auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second)) {
    return *bytes;
  }
  if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
    std::vector<uint8_t> out;
    out.reserve(list->size());
    for (const auto& item : *list) {
      if (const auto* i32 = std::get_if<int32_t>(&item)) {
        out.push_back(static_cast<uint8_t>(*i32));
      } else if (const auto* i64 = std::get_if<int64_t>(&item)) {
        out.push_back(static_cast<uint8_t>(*i64));
      }
    }
    return out;
  }
  return {};
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return {};
  }
  const int size =
      MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (size <= 1) {
    return {};
  }
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), size);
  return out;
}

std::wstring FileFromAsset(const std::string& asset) {
  std::string path = asset;
  if (path.rfind("file:///", 0) == 0) {
    path = path.substr(8);
  } else if (path.rfind("file://", 0) == 0) {
    path = path.substr(7);
  }
  std::replace(path.begin(), path.end(), '/', '\\');
  return Utf8ToWide(path);
}

std::wstring DirOf(HMODULE module) {
  wchar_t path[MAX_PATH];
  if (GetModuleFileNameW(module, path, MAX_PATH) == 0) {
    return {};
  }
  std::wstring dir(path);
  const auto slash = dir.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    dir.resize(slash + 1);
  }
  return dir;
}

bool FileExists(const std::wstring& path) {
  if (path.empty()) {
    return false;
  }
  const DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring ModelPath() {
  HMODULE module = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                         GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&ModelPath), &module);
  const std::wstring name = L"selfie_segmentation.onnx";
  std::wstring next_to_dll = DirOf(module) + name;
  if (FileExists(next_to_dll)) {
    return next_to_dll;
  }
  std::wstring next_to_exe = DirOf(nullptr) + name;
  if (FileExists(next_to_exe)) {
    return next_to_exe;
  }
  return next_to_dll;
}

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
      (std::max)(static_cast<float>(dst_w) / src_w,
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

bool DecodeStill(IWICImagingFactory* factory, IWICBitmapDecoder* decoder,
                 std::vector<uint8_t>* rgba, int* width, int* height) {
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame)) || frame == nullptr) {
    return false;
  }
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter))) {
    return false;
  }
  if (FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppRGBA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return false;
  }
  UINT w = 0;
  UINT h = 0;
  if (FAILED(converter->GetSize(&w, &h)) || w == 0 || h == 0) {
    return false;
  }
  rgba->assign(static_cast<size_t>(w) * h * 4, 0);
  const UINT stride = w * 4;
  if (FAILED(converter->CopyPixels(nullptr, stride,
                                   static_cast<UINT>(rgba->size()),
                                   rgba->data()))) {
    return false;
  }
  *width = static_cast<int>(w);
  *height = static_cast<int>(h);
  return true;
}

bool DecodeStillBytes(const std::vector<uint8_t>& bytes,
                      std::vector<uint8_t>* rgba, int* width, int* height) {
  if (bytes.empty()) {
    return false;
  }
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
    return false;
  }
  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream))) {
    return false;
  }
  if (FAILED(stream->InitializeFromMemory(
          const_cast<BYTE*>(bytes.data()),
          static_cast<DWORD>(bytes.size())))) {
    return false;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnDemand, &decoder))) {
    return false;
  }
  return DecodeStill(factory.Get(), decoder.Get(), rgba, width, height);
}

bool DecodeStillFile(const std::wstring& path, std::vector<uint8_t>* rgba,
                     int* width, int* height) {
  if (!FileExists(path)) {
    return false;
  }
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
    return false;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromFilename(
          path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
          &decoder))) {
    return false;
  }
  return DecodeStill(factory.Get(), decoder.Get(), rgba, width, height);
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
  LearningModel model_{nullptr};
  LearningModelSession session_{nullptr};
  bool load_failed_ = false;
  std::vector<float> input_;
  std::vector<uint8_t> mask256_;
  std::vector<uint8_t> mask_;
  std::vector<uint8_t> background_;
  std::vector<uint8_t> scratch_;

  bool EnsureSession() {
    std::lock_guard<std::mutex> lock(session_mutex_);
    if (session_) {
      return true;
    }
    if (load_failed_) {
      return false;
    }
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
    } catch (...) {
    }
    try {
      const std::wstring path = ModelPath();
      if (!FileExists(path)) {
        load_failed_ = true;
        return false;
      }
      model_ = LearningModel::LoadFromFilePath(path);
      session_ = LearningModelSession(model_);
      input_.assign(static_cast<size_t>(3) * kModel * kModel, 0.f);
      mask256_.assign(static_cast<size_t>(kModel) * kModel, 0);
      return true;
    } catch (...) {
      load_failed_ = true;
      model_ = nullptr;
      session_ = nullptr;
      return false;
    }
  }

  bool Segment(const uint8_t* rgba, int width, int height) {
    if (!EnsureSession() || rgba == nullptr || width <= 0 || height <= 0) {
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
    try {
      LearningModelBinding binding(session_);
      auto tensor = TensorFloat::CreateFromArray(
          winrt::single_threaded_vector<int64_t>({1, 3, kModel, kModel}),
          winrt::array_view<const float>(
              input_.data(),
              static_cast<uint32_t>(input_.size())));
      binding.Bind(L"pixel_values", tensor);
      const auto results = session_.Evaluate(binding, L"");
      const auto output =
          results.Outputs().Lookup(L"alphas").as<TensorFloat>();
      const auto view = output.GetAsVectorView();
      const uint32_t count =
          (std::min)(view.Size(), static_cast<uint32_t>(mask256_.size()));
      for (uint32_t i = 0; i < count; i++) {
        mask256_[i] = static_cast<uint8_t>(Clamp01(view.GetAt(i)) * 255.f + 0.5f);
      }
    } catch (...) {
      return false;
    }
    mask_.assign(static_cast<size_t>(width) * height, 0);
    ScaleMask(mask256_.data(), kModel, kModel, mask_.data(), width, height);
    return true;
  }

  void BlurBackground(const uint8_t* rgba, int width, int height, int intensity) {
    const size_t bytes = static_cast<size_t>(width) * height * 4;
    background_.assign(bytes, 0);
    if (intensity <= 0) {
      std::memcpy(background_.data(), rgba, bytes);
      return;
    }
    const float t = intensity / 100.f;
    const float factor = std::pow(1.f - t, 1.5f) * 0.88f + 0.12f;
    const int small_w =
        (std::max)(8, static_cast<int>(width * factor));
    const int small_h =
        (std::max)(8, static_cast<int>(height * factor));
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

std::string PersonBackgroundProcessor::Apply(
    const flutter::EncodableMap& args) {
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
      const std::wstring path = FileFromAsset(ReadString(args, "asset"));
      decoded = DecodeStillFile(path, &still, &still_w, &still_h);
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
