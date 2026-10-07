#ifndef FLUTTER_PLUGIN_LINUX_VIDEO_PROCESSOR_H_
#define FLUTTER_PLUGIN_LINUX_VIDEO_PROCESSOR_H_

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

/// Background blur and still replace on the Production video path.
class PersonBackgroundProcessor {
 public:
  PersonBackgroundProcessor();
  ~PersonBackgroundProcessor();

  PersonBackgroundProcessor(const PersonBackgroundProcessor&) = delete;
  PersonBackgroundProcessor& operator=(const PersonBackgroundProcessor&) =
      delete;

  /// Applies none / blur / replace. Returns ready, invalid, or unavailable.
  std::string Apply(FlValue* args);

  /// In-place RGBA transform. No-op for none or when segmentation fails.
  void Process(uint8_t* rgba, int width, int height);

  /// Fired once when runtime segmentation falls back to none (ADR-0017).
  void SetOnUnavailable(std::function<void()> callback);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // FLUTTER_PLUGIN_LINUX_VIDEO_PROCESSOR_H_
