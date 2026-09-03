#ifndef FLUTTER_PLUGIN_WINDOWS_WGC_CAPTURE_H_
#define FLUTTER_PLUGIN_WINDOWS_WGC_CAPTURE_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <memory>
#include <mutex>
#include <vector>

// Windows Graphics Capture production path. Picker thumbs stay on GDI
// (ADR-0025): WGC brands every captured window with a yellow border.
class WgcCapture {
 public:
  WgcCapture();
  ~WgcCapture();

  WgcCapture(const WgcCapture&) = delete;
  WgcCapture& operator=(const WgcCapture&) = delete;

  bool StartMonitor(HMONITOR monitor, bool cursor);
  bool StartWindow(HWND hwnd, bool cursor);
  bool StartDisplays(const std::vector<HMONITOR>& monitors,
                     const std::vector<RECT>& bounds, const RECT& virtual_bounds,
                     bool cursor);
  void Stop();
  void SetCursor(bool cursor);
  bool CopyLatest(int out_w, int out_h, std::vector<uint8_t>* dest);
  bool running() const { return running_; }

 private:
  struct Stream;
  struct Device;

  bool EnsureDevice();
  bool AddStream(HWND hwnd, HMONITOR monitor, const RECT& bounds, bool cursor);
  void CopyStreamFrame(Stream* stream, const void* src, int src_w, int src_h,
                       int src_stride);

  std::unique_ptr<Device> device_;
  std::mutex mutex_;
  std::vector<std::unique_ptr<Stream>> streams_;
  RECT virtual_bounds_{};
  bool running_ = false;
  bool cursor_ = true;
};

#endif  // FLUTTER_PLUGIN_WINDOWS_WGC_CAPTURE_H_
