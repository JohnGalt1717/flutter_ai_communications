#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "wgc_capture.h"

#include <d3d11.h>
#include <dxgi.h>
#include <unknwn.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstring>

using Microsoft::WRL::ComPtr;
using winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
using winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
using winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::SizeInt32;

namespace {

int MaxInt(int a, int b) { return a > b ? a : b; }

void ScaleCopyRgba(const uint8_t* src, int src_w, int src_h, int src_stride,
                   uint8_t* dest, int dest_w, int dest_h, int dest_x, int dest_y,
                   int dest_stride, int out_w, int out_h) {
  if (src_w <= 0 || src_h <= 0 || dest_w <= 0 || dest_h <= 0) {
    return;
  }
  for (int y = 0; y < dest_h; y++) {
    const int src_y = y * src_h / dest_h;
    const uint8_t* row = src + static_cast<size_t>(src_y) * src_stride;
    uint8_t* out = dest + static_cast<size_t>(dest_y + y) * dest_stride +
                   static_cast<size_t>(dest_x) * 4;
    for (int x = 0; x < dest_w; x++) {
      const int src_x = x * src_w / dest_w;
      const uint8_t* px = row + src_x * 4;
      out[0] = px[2];
      out[1] = px[1];
      out[2] = px[0];
      out[3] = 255;
      out += 4;
      (void)out_w;
      (void)out_h;
    }
  }
}

IDirect3DDevice WrapDevice(ID3D11Device* d3d) {
  ComPtr<IDXGIDevice> dxgi;
  if (FAILED(d3d->QueryInterface(IID_PPV_ARGS(&dxgi)))) {
    return nullptr;
  }
  winrt::com_ptr<::IInspectable> inspectable;
  if (FAILED(CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(),
                                                 inspectable.put()))) {
    return nullptr;
  }
  return inspectable.as<IDirect3DDevice>();
}

GraphicsCaptureItem ItemForMonitor(HMONITOR monitor) {
  auto interop =
      winrt::get_activation_factory<GraphicsCaptureItem,
                                    IGraphicsCaptureItemInterop>();
  GraphicsCaptureItem item{nullptr};
  if (FAILED(interop->CreateForMonitor(monitor,
                                       winrt::guid_of<GraphicsCaptureItem>(),
                                       winrt::put_abi(item)))) {
    return nullptr;
  }
  return item;
}

GraphicsCaptureItem ItemForWindow(HWND hwnd) {
  auto interop =
      winrt::get_activation_factory<GraphicsCaptureItem,
                                    IGraphicsCaptureItemInterop>();
  GraphicsCaptureItem item{nullptr};
  if (FAILED(interop->CreateForWindow(hwnd, winrt::guid_of<GraphicsCaptureItem>(),
                                      winrt::put_abi(item)))) {
    return nullptr;
  }
  return item;
}

}  // namespace

struct WgcCapture::Device {
  ComPtr<ID3D11Device> d3d;
  ComPtr<ID3D11DeviceContext> context;
  IDirect3DDevice winrt{nullptr};
};

struct WgcCapture::Stream {
  GraphicsCaptureItem item{nullptr};
  Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession session{nullptr};
  winrt::event_token arrived{};
  RECT bounds{};
  std::mutex mutex;
  std::vector<uint8_t> bgra;
  int width = 0;
  int height = 0;
};

WgcCapture::WgcCapture() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (winrt::hresult_error const&) {
    // STA already initialized by the Flutter runner is fine.
  }
}

WgcCapture::~WgcCapture() {
  Stop();
  device_.reset();
}

bool WgcCapture::EnsureDevice() {
  if (device_ != nullptr && device_->winrt) {
    return true;
  }
  auto next = std::make_unique<Device>();
  D3D_FEATURE_LEVEL level = D3D_FEATURE_LEVEL_11_0;
  const HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      nullptr, 0, D3D11_SDK_VERSION, &next->d3d, &level, &next->context);
  if (FAILED(hr) || next->d3d == nullptr) {
    return false;
  }
  next->winrt = WrapDevice(next->d3d.Get());
  if (!next->winrt) {
    return false;
  }
  device_ = std::move(next);
  return true;
}

bool WgcCapture::StartMonitor(HMONITOR monitor, bool cursor) {
  Stop();
  RECT bounds{};
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (monitor == nullptr || !GetMonitorInfoW(monitor, &info)) {
    return false;
  }
  bounds = info.rcMonitor;
  virtual_bounds_ = bounds;
  cursor_ = cursor;
  if (!AddStream(nullptr, monitor, bounds, cursor)) {
    Stop();
    return false;
  }
  running_ = true;
  return true;
}

bool WgcCapture::StartWindow(HWND hwnd, bool cursor) {
  Stop();
  if (hwnd == nullptr || !IsWindow(hwnd)) {
    return false;
  }
  RECT bounds{};
  if (!GetWindowRect(hwnd, &bounds)) {
    return false;
  }
  virtual_bounds_ = bounds;
  cursor_ = cursor;
  if (!AddStream(hwnd, nullptr, bounds, cursor)) {
    Stop();
    return false;
  }
  running_ = true;
  return true;
}

bool WgcCapture::StartDisplays(const std::vector<HMONITOR>& monitors,
                               const std::vector<RECT>& bounds,
                               const RECT& virtual_bounds, bool cursor) {
  Stop();
  if (monitors.empty() || monitors.size() != bounds.size()) {
    return false;
  }
  virtual_bounds_ = virtual_bounds;
  cursor_ = cursor;
  bool any = false;
  for (size_t i = 0; i < monitors.size(); i++) {
    if (AddStream(nullptr, monitors[i], bounds[i], cursor)) {
      any = true;
    }
  }
  running_ = any;
  return any;
}

bool WgcCapture::AddStream(HWND hwnd, HMONITOR monitor, const RECT& bounds,
                           bool cursor) {
  if (!EnsureDevice()) {
    return false;
  }
  GraphicsCaptureItem item{nullptr};
  try {
    item = hwnd != nullptr ? ItemForWindow(hwnd) : ItemForMonitor(monitor);
  } catch (winrt::hresult_error const&) {
    return false;
  }
  if (!item) {
    return false;
  }
  SizeInt32 size = item.Size();
  if (size.Width < 1 || size.Height < 1) {
    return false;
  }
  auto stream = std::make_unique<Stream>();
  stream->item = item;
  stream->bounds = bounds;
  try {
    stream->pool = Direct3D11CaptureFramePool::CreateFreeThreaded(
        device_->winrt, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
    stream->session = stream->pool.CreateCaptureSession(item);
    stream->session.IsCursorCaptureEnabled(cursor);
    try {
      stream->session.IsBorderRequired(false);
    } catch (winrt::hresult_error const&) {
      // Win10 has no IsBorderRequired. Production yellow border is allowed.
    }
    Stream* raw = stream.get();
    raw->arrived = raw->pool.FrameArrived(
        [this, raw](Direct3D11CaptureFramePool const& pool,
                    winrt::Windows::Foundation::IInspectable const&) {
          auto frame = pool.TryGetNextFrame();
          if (!frame) {
            return;
          }
          auto surface = frame.Surface();
          ComPtr<ID3D11Texture2D> texture;
          winrt::com_ptr<::Windows::Graphics::DirectX::Direct3D11::
                             IDirect3DDxgiInterfaceAccess>
              access;
          surface.as(access);
          if (!access ||
              FAILED(access->GetInterface(IID_PPV_ARGS(&texture))) ||
              texture == nullptr) {
            return;
          }
          D3D11_TEXTURE2D_DESC desc{};
          texture->GetDesc(&desc);
          desc.Usage = D3D11_USAGE_STAGING;
          desc.BindFlags = 0;
          desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
          desc.MiscFlags = 0;
          if (device_ == nullptr || device_->d3d == nullptr) {
            return;
          }
          ComPtr<ID3D11Texture2D> staging;
          if (FAILED(device_->d3d->CreateTexture2D(&desc, nullptr, &staging))) {
            return;
          }
          device_->context->CopyResource(staging.Get(), texture.Get());
          D3D11_MAPPED_SUBRESOURCE mapped{};
          if (FAILED(device_->context->Map(staging.Get(), 0, D3D11_MAP_READ, 0,
                                           &mapped))) {
            return;
          }
          CopyStreamFrame(raw, mapped.pData, static_cast<int>(desc.Width),
                          static_cast<int>(desc.Height),
                          static_cast<int>(mapped.RowPitch));
          device_->context->Unmap(staging.Get(), 0);
        });
    stream->session.StartCapture();
  } catch (winrt::hresult_error const&) {
    return false;
  }
  streams_.push_back(std::move(stream));
  return true;
}

void WgcCapture::CopyStreamFrame(Stream* stream, const void* src, int src_w,
                                 int src_h, int src_stride) {
  if (stream == nullptr || src == nullptr || src_w < 1 || src_h < 1) {
    return;
  }
  std::lock_guard<std::mutex> lock(stream->mutex);
  stream->width = src_w;
  stream->height = src_h;
  stream->bgra.assign(static_cast<size_t>(src_w) * src_h * 4, 0);
  const auto* row = static_cast<const uint8_t*>(src);
  for (int y = 0; y < src_h; y++) {
    std::memcpy(stream->bgra.data() + static_cast<size_t>(y) * src_w * 4, row,
                static_cast<size_t>(src_w) * 4);
    row += src_stride;
  }
}

void WgcCapture::Stop() {
  running_ = false;
  for (auto& stream : streams_) {
    try {
      if (stream->pool) {
        stream->pool.FrameArrived(stream->arrived);
      }
      if (stream->session) {
        stream->session.Close();
      }
      if (stream->pool) {
        stream->pool.Close();
      }
    } catch (winrt::hresult_error const&) {
    }
  }
  streams_.clear();
}

void WgcCapture::SetCursor(bool cursor) {
  cursor_ = cursor;
  for (auto& stream : streams_) {
    try {
      if (stream->session) {
        stream->session.IsCursorCaptureEnabled(cursor);
      }
    } catch (winrt::hresult_error const&) {
    }
  }
}

bool WgcCapture::CopyLatest(int out_w, int out_h, std::vector<uint8_t>* dest) {
  if (!running_ || dest == nullptr || out_w < 1 || out_h < 1) {
    return false;
  }
  dest->assign(static_cast<size_t>(out_w) * out_h * 4, 0);
  const int virt_w =
      MaxInt(1, virtual_bounds_.right - virtual_bounds_.left);
  const int virt_h =
      MaxInt(1, virtual_bounds_.bottom - virtual_bounds_.top);
  bool any = false;
  for (auto& stream : streams_) {
    std::vector<uint8_t> frame;
    int src_w = 0;
    int src_h = 0;
    RECT bounds{};
    {
      std::lock_guard<std::mutex> lock(stream->mutex);
      if (stream->bgra.empty()) {
        continue;
      }
      frame = stream->bgra;
      src_w = stream->width;
      src_h = stream->height;
      bounds = stream->bounds;
    }
    const int dx = (bounds.left - virtual_bounds_.left) * out_w / virt_w;
    const int dy = (bounds.top - virtual_bounds_.top) * out_h / virt_h;
    const int dw = MaxInt(1, (bounds.right - bounds.left) * out_w / virt_w);
    const int dh = MaxInt(1, (bounds.bottom - bounds.top) * out_h / virt_h);
    ScaleCopyRgba(frame.data(), src_w, src_h, src_w * 4, dest->data(), dw, dh,
                  dx, dy, out_w * 4, out_w, out_h);
    any = true;
  }
  return any;
}
