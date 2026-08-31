/// Requested or native pixel size and frame rate of a video send path.
final class VideoFormat {
  /// Creates a Video Format.
  const VideoFormat({
    required this.width,
    required this.height,
    this.frameRate = 30,
  });

  /// Default request: 1280×720 at 30 fps.
  static const VideoFormat defaultFormat = VideoFormat(
    width: 1280,
    height: 720,
    frameRate: 30,
  );

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Frames per second.
  final int frameRate;

  /// Pixel count used for nearest-match ordering.
  int get pixelCount => width * height;

  @override
  bool operator ==(Object other) =>
      other is VideoFormat &&
      other.width == width &&
      other.height == height &&
      other.frameRate == frameRate;

  @override
  int get hashCode => Object.hash(width, height, frameRate);

  @override
  String toString() => '${width}x$height@$frameRate';
}

/// Native Video Format the graph actually runs after negotiation.
typedef NativeVideoFormat = VideoFormat;
