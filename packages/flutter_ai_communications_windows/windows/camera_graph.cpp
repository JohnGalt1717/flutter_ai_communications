#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "camera_graph.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfobjects.h>
#include <mfreadwrite.h>
#include <objbase.h>
#include <wrl/client.h>

#include <algorithm>
#include <climits>
#include <cmath>
#include <cstring>

using Microsoft::WRL::ComPtr;

namespace {

std::string WideToUtf8(const wchar_t* wide) {
  if (wide == nullptr || wide[0] == 0) {
    return {};
  }
  const int size =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return {};
  }
  std::string out(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), size, nullptr, nullptr);
  out.resize(static_cast<size_t>(size - 1));
  return out;
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

HRESULT EnumVideoActivates(IMFActivate*** devices, UINT32* count) {
  ComPtr<IMFAttributes> attrs;
  HRESULT hr = MFCreateAttributes(&attrs, 1);
  if (FAILED(hr)) {
    return hr;
  }
  hr = attrs->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                      MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr)) {
    return hr;
  }
  return MFEnumDeviceSources(attrs.Get(), devices, count);
}

void ReleaseActivates(IMFActivate** devices, UINT32 count) {
  if (devices == nullptr) {
    return;
  }
  for (UINT32 i = 0; i < count; i++) {
    if (devices[i] != nullptr) {
      devices[i]->Release();
    }
  }
  CoTaskMemFree(devices);
}

std::string ActivateString(IMFActivate* activate, const GUID& key) {
  WCHAR* value = nullptr;
  UINT32 length = 0;
  if (FAILED(activate->GetAllocatedString(key, &value, &length)) ||
      value == nullptr) {
    return {};
  }
  std::string out = WideToUtf8(value);
  CoTaskMemFree(value);
  return out;
}

}  // namespace

CameraGraph::CameraGraph(flutter::TextureRegistrar* textures)
    : textures_(textures) {
  MFStartup(MF_VERSION, MFSTARTUP_LITE);
}

CameraGraph::~CameraGraph() {
  Stop();
  if (textures_ != nullptr && texture_id_ >= 0) {
    textures_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
  MFShutdown();
}

void CameraGraph::EnsureTexture() {
  if (texture_id_ >= 0 || textures_ == nullptr) {
    return;
  }
  texture_ = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
      [this](size_t width, size_t height) -> const FlutterDesktopPixelBuffer* {
        return CopyPixelBuffer(width, height);
      }));
  texture_id_ = textures_->RegisterTexture(texture_.get());
}

flutter::EncodableList CameraGraph::Enumerate() {
  flutter::EncodableList cameras;
  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  const HRESULT hr = EnumVideoActivates(&devices, &count);
  if (FAILED(hr) || devices == nullptr) {
    return cameras;
  }
  for (UINT32 i = 0; i < count; i++) {
    const std::string name =
        ActivateString(devices[i], MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME);
    const std::string id = ActivateString(
        devices[i], MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK);
    flutter::EncodableMap mode;
    mode[flutter::EncodableValue("width")] = flutter::EncodableValue(1280);
    mode[flutter::EncodableValue("height")] = flutter::EncodableValue(720);
    mode[flutter::EncodableValue("frameRate")] = flutter::EncodableValue(30);
    flutter::EncodableList modes;
    modes.push_back(flutter::EncodableValue(mode));
    flutter::EncodableMap camera;
    camera[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
    camera[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
    camera[flutter::EncodableValue("facing")] =
        flutter::EncodableValue(FacingFor(name, id));
    camera[flutter::EncodableValue("modes")] = flutter::EncodableValue(modes);
    cameras.push_back(flutter::EncodableValue(camera));
  }
  ReleaseActivates(devices, count);
  return cameras;
}

std::string CameraGraph::RequestPermission() {
  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  const HRESULT hr = EnumVideoActivates(&devices, &count);
  if (hr == E_ACCESSDENIED) {
    ReleaseActivates(devices, count);
    return "denied";
  }
  if (FAILED(hr) || devices == nullptr) {
    ReleaseActivates(devices, count);
    return "denied";
  }
  if (count == 0) {
    ReleaseActivates(devices, count);
    return "granted";
  }
  ComPtr<IMFMediaSource> source;
  const HRESULT activated =
      devices[0]->ActivateObject(IID_PPV_ARGS(&source));
  ReleaseActivates(devices, count);
  if (activated == E_ACCESSDENIED) {
    return "denied";
  }
  if (source != nullptr) {
    source->Shutdown();
  }
  if (FAILED(activated)) {
    return "denied";
  }
  return "granted";
}

CameraGraph::Mode CameraGraph::Nearest(const Mode& requested,
                                       const std::vector<Mode>& modes) {
  if (modes.empty()) {
    return requested;
  }
  std::vector<Mode> higher;
  for (const auto& mode : modes) {
    if (mode.PixelCount() >= requested.PixelCount()) {
      higher.push_back(mode);
    }
  }
  const std::vector<Mode>& band = higher.empty() ? modes : higher;
  int best_pixels = higher.empty() ? 0 : INT_MAX;
  if (higher.empty()) {
    for (const auto& mode : band) {
      best_pixels = (std::max)(best_pixels, mode.PixelCount());
    }
  } else {
    for (const auto& mode : band) {
      best_pixels = (std::min)(best_pixels, mode.PixelCount());
    }
  }
  Mode best = band.front();
  int best_distance = INT_MAX;
  for (const auto& mode : band) {
    if (mode.PixelCount() != best_pixels) {
      continue;
    }
    const int distance = std::abs(mode.fps - requested.fps);
    if (distance < best_distance ||
        (distance == best_distance && mode.fps >= requested.fps &&
         best.fps < requested.fps)) {
      best = mode;
      best_distance = distance;
    }
  }
  return best;
}

std::string CameraGraph::FacingFor(const std::string& name,
                                   const std::string& symlink) {
  const std::string haystack = ToLower(name + " " + symlink);
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

flutter::EncodableMap CameraGraph::Start(const std::string& camera_id,
                                         int width,
                                         int height,
                                         int frame_rate,
                                         bool enabled,
                                         bool muted) {
  EnsureTexture();
  if (texture_id_ < 0) {
    flutter::EncodableMap failed;
    failed[flutter::EncodableValue("status")] = flutter::EncodableValue("failed");
    return failed;
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
    if (textures_ != nullptr && texture_id_ >= 0) {
      textures_->MarkTextureFrameAvailable(texture_id_);
    }
    flutter::EncodableMap started;
    started[flutter::EncodableValue("status")] =
        flutter::EncodableValue("started");
    started[flutter::EncodableValue("textureId")] =
        flutter::EncodableValue(texture_id_);
    started[flutter::EncodableValue("width")] = flutter::EncodableValue(width_);
    started[flutter::EncodableValue("height")] =
        flutter::EncodableValue(height_);
    started[flutter::EncodableValue("frameRate")] =
        flutter::EncodableValue(frame_rate_);
    return started;
  }
  if (!StartCapture(camera_id, request_width_, request_height_,
                    request_frame_rate_)) {
    flutter::EncodableMap unavailable;
    unavailable[flutter::EncodableValue("status")] =
        flutter::EncodableValue("unavailable");
    return unavailable;
  }
  flutter::EncodableMap started;
  started[flutter::EncodableValue("status")] = flutter::EncodableValue("started");
  started[flutter::EncodableValue("textureId")] =
      flutter::EncodableValue(texture_id_);
  started[flutter::EncodableValue("width")] = flutter::EncodableValue(width_);
  started[flutter::EncodableValue("height")] = flutter::EncodableValue(height_);
  started[flutter::EncodableValue("frameRate")] =
      flutter::EncodableValue(frame_rate_);
  return started;
}

void CameraGraph::Stop() {
  StopCapture();
}

void CameraGraph::Select(const std::string& camera_id) {
  Start(camera_id, request_width_, request_height_, request_frame_rate_,
        enabled_.load(), muted_.load());
}

void CameraGraph::SetEnabled(bool enabled) {
  enabled_.store(enabled);
  if (!enabled) {
    StopCapture();
    std::lock_guard<std::mutex> lock(mutex_);
    FillBlackLocked();
    if (textures_ != nullptr && texture_id_ >= 0) {
      textures_->MarkTextureFrameAvailable(texture_id_);
    }
    return;
  }
  StartCapture(camera_id_, request_width_, request_height_,
               request_frame_rate_);
}

flutter::EncodableMap CameraGraph::Stats() const {
  flutter::EncodableMap stats;
  stats[flutter::EncodableValue("frameCount")] =
      flutter::EncodableValue(frame_count_.load());
  stats[flutter::EncodableValue("liveFrames")] =
      flutter::EncodableValue(live_frames_.load());
  return stats;
}

void CameraGraph::SetMuted(bool muted) {
  muted_.store(muted);
  if (muted) {
    std::lock_guard<std::mutex> lock(mutex_);
    FillBlackLocked();
  }
  if (textures_ != nullptr && texture_id_ >= 0) {
    textures_->MarkTextureFrameAvailable(texture_id_);
  }
}

void CameraGraph::StopCapture() {
  running_.store(false);
  if (reader_ != nullptr) {
    reader_->Flush(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS));
  }
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  if (reader_ != nullptr) {
    reader_->Release();
    reader_ = nullptr;
  }
  if (source_ != nullptr) {
    source_->Shutdown();
    source_->Release();
    source_ = nullptr;
  }
}

bool CameraGraph::StartCapture(const std::string& camera_id,
                               int width,
                               int height,
                               int frame_rate) {
  StopCapture();
  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  if (FAILED(EnumVideoActivates(&devices, &count)) || devices == nullptr ||
      count == 0) {
    ReleaseActivates(devices, count);
    return false;
  }
  IMFActivate* chosen = nullptr;
  IMFActivate* user = nullptr;
  for (UINT32 i = 0; i < count; i++) {
    const std::string id = ActivateString(
        devices[i], MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK);
    const std::string name =
        ActivateString(devices[i], MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME);
    if (!camera_id.empty() && id == camera_id) {
      chosen = devices[i];
      break;
    }
    if (user == nullptr && FacingFor(name, id) == "user") {
      user = devices[i];
    }
  }
  if (chosen == nullptr) {
    if (!camera_id.empty()) {
      ReleaseActivates(devices, count);
      return false;
    }
    chosen = user != nullptr ? user : devices[0];
  }
  camera_id_ = ActivateString(
      chosen, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK);

  ComPtr<IMFMediaSource> source;
  HRESULT hr = chosen->ActivateObject(IID_PPV_ARGS(&source));
  ReleaseActivates(devices, count);
  if (FAILED(hr) || source == nullptr) {
    return false;
  }
  ComPtr<IMFAttributes> reader_attrs;
  hr = MFCreateAttributes(&reader_attrs, 2);
  if (FAILED(hr)) {
    source->Shutdown();
    return false;
  }
  reader_attrs->SetUINT32(MF_READWRITE_DISABLE_CONVERTERS, FALSE);
  reader_attrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
  ComPtr<IMFSourceReader> reader;
  hr = MFCreateSourceReaderFromMediaSource(source.Get(), reader_attrs.Get(),
                                           &reader);
  if (FAILED(hr) || reader == nullptr) {
    source->Shutdown();
    return false;
  }
  reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),
                             FALSE);
  reader->SetStreamSelection(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), TRUE);

  Mode requested;
  requested.width = width;
  requested.height = height;
  requested.fps = frame_rate;
  Mode native;
  if (!PickNativeMode(reader.Get(), requested, &native)) {
    native = requested;
  }
  width_ = native.width;
  height_ = native.height;
  frame_rate_ = native.fps;
  if (!ConfigureRgb32(reader.Get(), native)) {
    source->Shutdown();
    return false;
  }
  ReadCurrentFormat(reader.Get());

  source_ = source.Detach();
  reader_ = reader.Detach();
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

bool CameraGraph::ConfigureRgb32(IMFSourceReader* reader, const Mode& native) {
  const DWORD stream =
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
  ComPtr<IMFMediaType> sized;
  if (SUCCEEDED(MFCreateMediaType(&sized))) {
    sized->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    sized->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    MFSetAttributeSize(sized.Get(), MF_MT_FRAME_SIZE,
                       static_cast<UINT32>(native.width),
                       static_cast<UINT32>(native.height));
    MFSetAttributeRatio(sized.Get(), MF_MT_FRAME_RATE,
                        static_cast<UINT32>(native.fps), 1);
    MFSetAttributeRatio(sized.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    sized->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    sized->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
    if (SUCCEEDED(reader->SetCurrentMediaType(stream, nullptr, sized.Get()))) {
      return true;
    }
  }
  ComPtr<IMFMediaType> partial;
  if (SUCCEEDED(MFCreateMediaType(&partial))) {
    partial->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    partial->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    if (SUCCEEDED(
            reader->SetCurrentMediaType(stream, nullptr, partial.Get()))) {
      return true;
    }
  }
  return false;
}

void CameraGraph::ReadCurrentFormat(IMFSourceReader* reader) {
  ComPtr<IMFMediaType> current;
  if (FAILED(reader->GetCurrentMediaType(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &current)) ||
      current == nullptr) {
    return;
  }
  UINT32 native_width = 0;
  UINT32 native_height = 0;
  if (SUCCEEDED(MFGetAttributeSize(current.Get(), MF_MT_FRAME_SIZE,
                                   &native_width, &native_height)) &&
      native_width > 0 && native_height > 0) {
    width_ = static_cast<int>(native_width);
    height_ = static_cast<int>(native_height);
  }
  UINT32 num = 30;
  UINT32 den = 1;
  if (SUCCEEDED(MFGetAttributeRatio(current.Get(), MF_MT_FRAME_RATE, &num,
                                    &den)) &&
      den != 0) {
    frame_rate_ = static_cast<int>((num + den / 2) / den);
  }
}

bool CameraGraph::PickNativeMode(IMFSourceReader* reader,
                                 const Mode& requested,
                                 Mode* out) {
  std::vector<Mode> modes;
  for (DWORD index = 0;; index++) {
    ComPtr<IMFMediaType> type;
    const HRESULT hr = reader->GetNativeMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), index, &type);
    if (hr == MF_E_NO_MORE_TYPES) {
      break;
    }
    if (FAILED(hr) || type == nullptr) {
      break;
    }
    UINT32 native_width = 0;
    UINT32 native_height = 0;
    if (FAILED(MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &native_width,
                                  &native_height))) {
      continue;
    }
    UINT32 num = 30;
    UINT32 den = 1;
    MFGetAttributeRatio(type.Get(), MF_MT_FRAME_RATE, &num, &den);
    Mode mode;
    mode.width = static_cast<int>(native_width);
    mode.height = static_cast<int>(native_height);
    mode.fps = den == 0 ? 30 : static_cast<int>((num + den / 2) / den);
    modes.push_back(mode);
  }
  if (modes.empty()) {
    return false;
  }
  *out = Nearest(requested, modes);
  return true;
}

void CameraGraph::CaptureLoop() {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  while (running_.load()) {
    if (reader_ == nullptr) {
      break;
    }
    ComPtr<IMFSample> sample;
    DWORD stream_index = 0;
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    const HRESULT hr = reader_->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),
                                           0, &stream_index, &flags,
                                           &timestamp, &sample);
    if (!running_.load()) {
      break;
    }
    if (FAILED(hr)) {
      break;
    }
    if (sample != nullptr) {
      frame_count_.fetch_add(1);
    }
    if (muted_.load() || !enabled_.load()) {
      std::lock_guard<std::mutex> lock(mutex_);
      FillBlackLocked();
    } else if (sample != nullptr) {
      CopySample(sample.Get());
    }
    if (textures_ != nullptr && texture_id_ >= 0) {
      textures_->MarkTextureFrameAvailable(texture_id_);
    }
  }
  if (com == S_OK) {
    CoUninitialize();
  }
}

void CameraGraph::CopySample(void* raw_sample) {
  auto* sample = static_cast<IMFSample*>(raw_sample);
  ComPtr<IMFMediaBuffer> buffer;
  if (FAILED(sample->ConvertToContiguousBuffer(&buffer)) || buffer == nullptr) {
    return;
  }
  ComPtr<IMF2DBuffer> buffer2d;
  BYTE* src = nullptr;
  LONG pitch = 0;
  DWORD max_length = 0;
  DWORD current_length = 0;
  bool locked_2d = false;
  if (SUCCEEDED(buffer.As(&buffer2d)) && buffer2d != nullptr &&
      SUCCEEDED(buffer2d->Lock2D(&src, &pitch))) {
    locked_2d = true;
  } else if (FAILED(buffer->Lock(&src, &max_length, &current_length))) {
    return;
  }
  if (src == nullptr) {
    if (locked_2d) {
      buffer2d->Unlock2D();
    } else {
      buffer->Unlock();
    }
    return;
  }
  const LONG stride = locked_2d ? (pitch == 0 ? width_ * 4 : pitch)
                                : width_ * 4;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    const size_t bytes = static_cast<size_t>(width_) * height_ * 4;
    if (front_.size() != bytes) {
      front_.assign(bytes, 0);
    }
    bool live = false;
    for (int y = 0; y < height_; y++) {
      const int src_y = locked_2d ? y : (height_ - 1 - y);
      const BYTE* row = src + static_cast<ptrdiff_t>(stride) * src_y;
      uint8_t* dst = front_.data() + static_cast<size_t>(y) * width_ * 4;
      for (int x = 0; x < width_; x++) {
        const BYTE* px = row + x * 4;
        dst[x * 4 + 0] = px[2];
        dst[x * 4 + 1] = px[1];
        dst[x * 4 + 2] = px[0];
        dst[x * 4 + 3] = 255;
        if (!live && (px[0] > 8 || px[1] > 8 || px[2] > 8)) {
          live = true;
        }
      }
    }
    if (live) {
      live_frames_.fetch_add(1);
    }
  }
  if (locked_2d) {
    buffer2d->Unlock2D();
  } else {
    buffer->Unlock();
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

const FlutterDesktopPixelBuffer* CameraGraph::CopyPixelBuffer(size_t width,
                                                              size_t height) {
  std::unique_lock<std::mutex> lock(mutex_);
  if (front_.empty()) {
    return nullptr;
  }
  if (!pixel_buffer_) {
    pixel_buffer_ = std::make_unique<FlutterDesktopPixelBuffer>();
    pixel_buffer_->release_callback = [](void* context) {
      auto* mutex = static_cast<std::mutex*>(context);
      mutex->unlock();
    };
  }
  pixel_buffer_->buffer = front_.data();
  pixel_buffer_->width = static_cast<size_t>(width_);
  pixel_buffer_->height = static_cast<size_t>(height_);
  pixel_buffer_->release_context = &mutex_;
  lock.release();
  return pixel_buffer_.get();
}
