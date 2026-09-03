#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "screen_graph.h"

#include <dwmapi.h>

#include <algorithm>
#include <cmath>
#include <cstring>

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

flutter::EncodableMap SourceMap(const std::string& id, const std::string& name,
                                const std::string& kind, const RECT& bounds,
                                bool can_preview) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  map[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
  map[flutter::EncodableValue("kind")] = flutter::EncodableValue(kind);
  map[flutter::EncodableValue("x")] = flutter::EncodableValue(bounds.left);
  map[flutter::EncodableValue("y")] = flutter::EncodableValue(bounds.top);
  map[flutter::EncodableValue("width")] =
      flutter::EncodableValue(bounds.right - bounds.left);
  map[flutter::EncodableValue("height")] =
      flutter::EncodableValue(bounds.bottom - bounds.top);
  map[flutter::EncodableValue("canPreview")] =
      flutter::EncodableValue(can_preview);
  return map;
}

int MaxInt(int a, int b) { return a > b ? a : b; }
int MinInt(int a, int b) { return a < b ? a : b; }
int ClampInt(int value, int lo, int hi) {
  if (value < lo) {
    return lo;
  }
  if (value > hi) {
    return hi;
  }
  return value;
}

void FillExcludedWindow(HDC mem, HWND hwnd, const RECT& src_rect, int src_w,
                        int src_h, int out_w, int out_h) {
  if (hwnd == nullptr) {
    return;
  }
  RECT window_rect{};
  if (!GetWindowRect(hwnd, &window_rect)) {
    return;
  }
  RECT local = window_rect;
  local.left -= src_rect.left;
  local.top -= src_rect.top;
  local.right -= src_rect.left;
  local.bottom -= src_rect.top;
  const double scale_x = static_cast<double>(out_w) / src_w;
  const double scale_y = static_cast<double>(out_h) / src_h;
  const int x0 = ClampInt(static_cast<int>(local.left * scale_x), 0, out_w);
  const int y0 = ClampInt(static_cast<int>(local.top * scale_y), 0, out_h);
  const int x1 = ClampInt(static_cast<int>(local.right * scale_x), 0, out_w);
  const int y1 = ClampInt(static_cast<int>(local.bottom * scale_y), 0, out_h);
  HBRUSH brush = CreateSolidBrush(RGB(0, 0, 0));
  RECT fill{x0, y0, x1, y1};
  FillRect(mem, &fill, brush);
  DeleteObject(brush);
}

void BltRectToRgba(HDC src, const RECT& src_rect, int out_w, int out_h,
                   std::vector<uint8_t>* dest, HWND exclude_a, HWND exclude_b) {
  if (out_w <= 0 || out_h <= 0) {
    dest->clear();
    return;
  }
  dest->assign(static_cast<size_t>(out_w) * out_h * 4, 0);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = out_w;
  info.bmiHeader.biHeight = -out_h;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HDC mem = CreateCompatibleDC(src);
  if (mem == nullptr) {
    return;
  }
  HBITMAP bitmap = CreateDIBSection(mem, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (bitmap == nullptr || bits == nullptr) {
    if (bitmap) {
      DeleteObject(bitmap);
    }
    DeleteDC(mem);
    return;
  }
  HGDIOBJ old = SelectObject(mem, bitmap);
  const int src_w = MaxInt(1, static_cast<int>(src_rect.right - src_rect.left));
  const int src_h = MaxInt(1, static_cast<int>(src_rect.bottom - src_rect.top));
  SetStretchBltMode(mem, HALFTONE);
  StretchBlt(mem, 0, 0, out_w, out_h, src, src_rect.left, src_rect.top, src_w,
             src_h, SRCCOPY);
  FillExcludedWindow(mem, exclude_a, src_rect, src_w, src_h, out_w, out_h);
  FillExcludedWindow(mem, exclude_b, src_rect, src_w, src_h, out_w, out_h);
  auto* bgra = static_cast<uint8_t*>(bits);
  for (int i = 0; i < out_w * out_h; i++) {
    (*dest)[static_cast<size_t>(i) * 4 + 0] = bgra[static_cast<size_t>(i) * 4 + 2];
    (*dest)[static_cast<size_t>(i) * 4 + 1] = bgra[static_cast<size_t>(i) * 4 + 1];
    (*dest)[static_cast<size_t>(i) * 4 + 2] = bgra[static_cast<size_t>(i) * 4 + 0];
    (*dest)[static_cast<size_t>(i) * 4 + 3] = 255;
  }
  SelectObject(mem, old);
  DeleteObject(bitmap);
  DeleteDC(mem);
}

}  // namespace

ScreenGraph::ScreenGraph(flutter::TextureRegistrar* textures, HWND flutter_window)
    : textures_(textures), flutter_window_(flutter_window) {}

ScreenGraph::~ScreenGraph() {
  Stop();
  EndPick();
  HideFrame();
  if (frame_class_ != 0) {
    UnregisterClass(L"FacShareFrame", GetModuleHandle(nullptr));
    frame_class_ = 0;
  }
}

void ScreenGraph::RefreshSources() {
  sources_.clear();
  struct MonitorCtx {
    std::vector<Source>* sources;
    int index;
  } ctx{&sources_, 0};
  EnumDisplayMonitors(
      nullptr, nullptr,
      [](HMONITOR monitor, HDC, LPRECT, LPARAM data) -> BOOL {
        auto* ctx = reinterpret_cast<MonitorCtx*>(data);
        MONITORINFOEXW info{};
        info.cbSize = sizeof(info);
        if (!GetMonitorInfoW(monitor, &info)) {
          return TRUE;
        }
        Source source;
        source.id = "display-" + std::to_string(ctx->index);
        source.name = WideToUtf8(info.szDevice);
        if (source.name.empty()) {
          source.name = "Display " + std::to_string(ctx->index + 1);
        }
        source.kind = "display";
        source.bounds = info.rcMonitor;
        source.monitor = monitor;
        ctx->sources->push_back(source);
        ctx->index++;
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&ctx));

  RECT virtual_bounds;
  virtual_bounds.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  virtual_bounds.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  virtual_bounds.right = virtual_bounds.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
  virtual_bounds.bottom = virtual_bounds.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
  Source all;
  all.id = "all-displays";
  all.name = "All displays";
  all.kind = "allDisplays";
  all.bounds = virtual_bounds;
  sources_.push_back(all);

  struct WindowCtx {
    std::vector<Source>* sources;
    HWND self;
    HWND frame;
  } windows{&sources_, flutter_window_, frame_window_};
  EnumWindows(
      [](HWND hwnd, LPARAM data) -> BOOL {
        auto* ctx = reinterpret_cast<WindowCtx*>(data);
        if (hwnd == ctx->self || hwnd == ctx->frame) {
          return TRUE;
        }
        if (!IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER) != nullptr) {
          return TRUE;
        }
        const LONG_PTR ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        if ((ex & WS_EX_TOOLWINDOW) != 0) {
          return TRUE;
        }
        wchar_t title[512];
        if (GetWindowTextW(hwnd, title, 512) <= 0) {
          return TRUE;
        }
        RECT bounds{};
        if (!GetWindowRect(hwnd, &bounds) || bounds.right <= bounds.left) {
          return TRUE;
        }
        Source source;
        source.id = "window-" + std::to_string(reinterpret_cast<uintptr_t>(hwnd));
        source.name = WideToUtf8(title);
        source.kind = "window";
        source.bounds = bounds;
        source.hwnd = hwnd;
        ctx->sources->push_back(source);
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&windows));
}

flutter::EncodableList ScreenGraph::Enumerate() {
  std::lock_guard<std::mutex> lock(mutex_);
  RefreshSources();
  flutter::EncodableList list;
  for (const auto& source : sources_) {
    list.push_back(flutter::EncodableValue(
        SourceMap(source.id, source.name, source.kind, source.bounds, true)));
  }
  return list;
}

std::string ScreenGraph::RequestPermission() { return "granted"; }

void ScreenGraph::ClearPreviewsLocked() {
  for (auto& [id, preview] : previews_) {
    if (textures_ != nullptr && preview->texture_id >= 0) {
      textures_->UnregisterTexture(preview->texture_id);
    }
  }
  previews_.clear();
}

flutter::EncodableMap ScreenGraph::BeginPick() {
  std::lock_guard<std::mutex> lock(mutex_);
  ClearPreviewsLocked();
  RefreshSources();
  flutter::EncodableMap previews;
  for (const auto& source : sources_) {
    auto preview = std::make_unique<Preview>();
    preview->texture = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [preview_ptr = preview.get()](size_t, size_t)
                -> const FlutterDesktopPixelBuffer* {
              if (preview_ptr->pixels.empty()) {
                return nullptr;
              }
              if (!preview_ptr->pixel_buffer) {
                preview_ptr->pixel_buffer =
                    std::make_unique<FlutterDesktopPixelBuffer>();
              }
              preview_ptr->pixel_buffer->buffer = preview_ptr->pixels.data();
              preview_ptr->pixel_buffer->width =
                  static_cast<size_t>(preview_ptr->width);
              preview_ptr->pixel_buffer->height =
                  static_cast<size_t>(preview_ptr->height);
              preview_ptr->pixel_buffer->release_callback = nullptr;
              return preview_ptr->pixel_buffer.get();
            }));
    preview->texture_id = textures_->RegisterTexture(preview->texture.get());
    CaptureSourceLocked(source, preview->width, preview->height,
                        &preview->pixels);
    textures_->MarkTextureFrameAvailable(preview->texture_id);
    previews[flutter::EncodableValue(source.id)] =
        flutter::EncodableValue(static_cast<int32_t>(preview->texture_id));
    previews_[source.id] = std::move(preview);
  }
  flutter::EncodableMap out;
  out[flutter::EncodableValue("previews")] = flutter::EncodableValue(previews);
  return out;
}

void ScreenGraph::EndPick() {
  std::lock_guard<std::mutex> lock(mutex_);
  ClearPreviewsLocked();
}

void ScreenGraph::Indicate(const std::string& source_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (source_id.empty()) {
    HideFrame();
    return;
  }
  for (const auto& source : sources_) {
    if (source.id == source_id) {
      ShowFrame(source.bounds);
      return;
    }
  }
}

void ScreenGraph::EnsureSendTexture() {
  if (send_texture_id_ >= 0 || textures_ == nullptr) {
    return;
  }
  send_texture_ = std::make_unique<flutter::TextureVariant>(
      flutter::PixelBufferTexture(
          [this](size_t width, size_t height) -> const FlutterDesktopPixelBuffer* {
            return CopySendBuffer(width, height);
          }));
  send_texture_id_ = textures_->RegisterTexture(send_texture_.get());
}

flutter::EncodableMap ScreenGraph::Start(const std::string& source_id,
                                         bool include_audio, bool cursor,
                                         bool motion) {
  Stop();
  std::lock_guard<std::mutex> lock(mutex_);
  RefreshSources();
  const Source* found = nullptr;
  for (const auto& source : sources_) {
    if (source.id == source_id) {
      found = &source;
      break;
    }
  }
  flutter::EncodableMap result;
  if (found == nullptr) {
    result[flutter::EncodableValue("status")] =
        flutter::EncodableValue("unavailable");
    result[flutter::EncodableValue("reason")] = flutter::EncodableValue("none");
    return result;
  }
  cursor_ = cursor;
  motion_ = motion;
  send_id_ = found->id;
  const int src_w = static_cast<int>(found->bounds.right - found->bounds.left);
  const int src_h = static_cast<int>(found->bounds.bottom - found->bounds.top);
  const int src_w_safe = src_w > 1 ? src_w : 1;
  const int src_h_safe = src_h > 1 ? src_h : 1;
  double scale = 1.0;
  if (src_w_safe > 1920 || src_h_safe > 1080) {
    const double scale_w = 1920.0 / src_w_safe;
    const double scale_h = 1080.0 / src_h_safe;
    scale = scale_w < scale_h ? scale_w : scale_h;
  }
  send_width_ = static_cast<int>(std::round(src_w_safe * scale));
  send_height_ = static_cast<int>(std::round(src_h_safe * scale));
  if (send_width_ < 1) {
    send_width_ = 1;
  }
  if (send_height_ < 1) {
    send_height_ = 1;
  }
  EnsureSendTexture();
  ShowFrame(found->bounds);
  running_ = true;
  capture_thread_ = std::thread([this] { CaptureLoop(); });
  result[flutter::EncodableValue("status")] = flutter::EncodableValue("started");
  result[flutter::EncodableValue("textureId")] =
      flutter::EncodableValue(static_cast<int32_t>(send_texture_id_));
  result[flutter::EncodableValue("width")] = flutter::EncodableValue(send_width_);
  result[flutter::EncodableValue("height")] =
      flutter::EncodableValue(send_height_);
  result[flutter::EncodableValue("frameRate")] =
      flutter::EncodableValue(motion ? 30 : 5);
  result[flutter::EncodableValue("systemAudio")] =
      flutter::EncodableValue(false);
  (void)include_audio;
  return result;
}

void ScreenGraph::Stop() {
  running_ = false;
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  HideFrame();
  send_id_.clear();
}

bool ScreenGraph::SetIncludeSystemAudio(bool enabled) {
  (void)enabled;
  return false;
}

void ScreenGraph::SetMotion(bool motion) { motion_ = motion; }

void ScreenGraph::SetCursor(bool cursor) { cursor_ = cursor; }

void ScreenGraph::CaptureLoop() {
  while (running_) {
    Source snapshot;
    int out_w = 0;
    int out_h = 0;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      out_w = send_width_;
      out_h = send_height_;
      for (const auto& source : sources_) {
        if (source.id == send_id_) {
          snapshot = source;
          if (source.hwnd != nullptr) {
            GetWindowRect(source.hwnd, &snapshot.bounds);
          }
          break;
        }
      }
    }
    std::vector<uint8_t> frame;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      CaptureSourceLocked(snapshot, out_w, out_h, &frame);
      send_front_.swap(frame);
    }
    if (textures_ != nullptr && send_texture_id_ >= 0) {
      textures_->MarkTextureFrameAvailable(send_texture_id_);
    }
    const int fps = motion_ ? 30 : 5;
    Sleep(static_cast<DWORD>(1000 / (fps > 0 ? fps : 1)));
  }
}

void ScreenGraph::CaptureSourceLocked(const Source& source, int out_w, int out_h,
                                      std::vector<uint8_t>* dest) {
  HDC screen = GetDC(nullptr);
  RECT bounds = source.bounds;
  HWND exclude = source.kind == "window" ? nullptr : flutter_window_;
  BltRectToRgba(screen, bounds, out_w, out_h, dest, exclude, frame_window_);
  ReleaseDC(nullptr, screen);
}

void ScreenGraph::ShowFrame(const RECT& bounds) {
  if (frame_class_ == 0) {
    WNDCLASS wc{};
    wc.lpfnWndProc = FrameWndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"FacShareFrame";
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    frame_class_ = RegisterClass(&wc);
    if (frame_class_ == 0 && GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
      frame_class_ = 1;
    }
  }
  if (frame_window_ == nullptr) {
    frame_window_ = CreateWindowEx(
        WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW |
            WS_EX_NOACTIVATE,
        L"FacShareFrame", L"", WS_POPUP,
        bounds.left, bounds.top, bounds.right - bounds.left,
        bounds.bottom - bounds.top, nullptr, nullptr, GetModuleHandle(nullptr),
        this);
    SetLayeredWindowAttributes(frame_window_, 0, 255, LWA_ALPHA);
  } else {
    SetWindowPos(frame_window_, HWND_TOPMOST, bounds.left, bounds.top,
                 bounds.right - bounds.left, bounds.bottom - bounds.top,
                 SWP_NOACTIVATE);
  }
  ShowWindow(frame_window_, SW_SHOWNOACTIVATE);
  InvalidateRect(frame_window_, nullptr, TRUE);
}

void ScreenGraph::HideFrame() {
  if (frame_window_ != nullptr) {
    ShowWindow(frame_window_, SW_HIDE);
  }
}

LRESULT CALLBACK ScreenGraph::FrameWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                           LPARAM lparam) {
  if (msg == WM_PAINT) {
    PAINTSTRUCT ps;
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT rect;
    GetClientRect(hwnd, &rect);
    HBRUSH brush = CreateSolidBrush(RGB(196, 32, 32));
    FrameRect(hdc, &rect, brush);
    InflateRect(&rect, -3, -3);
    FrameRect(hdc, &rect, brush);
    DeleteObject(brush);
    EndPaint(hwnd, &ps);
    return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

const FlutterDesktopPixelBuffer* ScreenGraph::CopySendBuffer(size_t,
                                                             size_t) {
  std::unique_lock<std::mutex> lock(mutex_);
  if (send_front_.empty()) {
    return nullptr;
  }
  if (!send_pixel_buffer_) {
    send_pixel_buffer_ = std::make_unique<FlutterDesktopPixelBuffer>();
    send_pixel_buffer_->release_callback = [](void* context) {
      static_cast<std::mutex*>(context)->unlock();
    };
  }
  send_pixel_buffer_->buffer = send_front_.data();
  send_pixel_buffer_->width = static_cast<size_t>(send_width_);
  send_pixel_buffer_->height = static_cast<size_t>(send_height_);
  send_pixel_buffer_->release_context = &mutex_;
  lock.release();
  return send_pixel_buffer_.get();
}

const FlutterDesktopPixelBuffer* ScreenGraph::CopyPreviewBuffer(Preview*) {
  return nullptr;
}
