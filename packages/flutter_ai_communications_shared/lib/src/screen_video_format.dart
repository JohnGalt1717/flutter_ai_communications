import 'video_format.dart';

/// Teams-style requested Video Format for screen send (ADR-0027).
abstract final class ScreenVideoFormat {
  /// Max send width.
  static const int capWidth = 1920;

  /// Max send height.
  static const int capHeight = 1080;

  /// Documents / Screen motion off.
  static const int documentsFps = 5;

  /// Screen motion on.
  static const int motionFps = 30;

  /// Physical raster capped at 1920×1080, keeping aspect ratio.
  static VideoFormat request({
    required int width,
    required int height,
    required bool motion,
  }) {
    final fps = motion ? motionFps : documentsFps;
    if (width <= 0 || height <= 0) {
      return VideoFormat(width: capWidth, height: capHeight, frameRate: fps);
    }
    if (width <= capWidth && height <= capHeight) {
      return VideoFormat(width: width, height: height, frameRate: fps);
    }
    final scaleW = capWidth / width;
    final scaleH = capHeight / height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    return VideoFormat(
      width: (width * scale).round().clamp(1, capWidth),
      height: (height * scale).round().clamp(1, capHeight),
      frameRate: fps,
    );
  }
}
