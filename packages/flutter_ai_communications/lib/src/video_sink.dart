import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// One Production video path observation for a [VideoSink].
final class VideoPathSnapshot {
  /// Creates a path snapshot.
  const VideoPathSnapshot({
    required this.generation,
    required this.muteVideo,
    required this.cameraOff,
    required this.processor,
    this.surface,
  });

  /// Production video path generation. Increments when the graph starts.
  final int generation;

  /// Mute-video: black frames, graph stays up.
  final bool muteVideo;

  /// Camera-off or no running graph. Hardware is not feeding the path.
  final bool cameraOff;

  /// Selected Video processor. v1 is [NoneVideoProcessor].
  final VideoProcessor processor;

  /// Local send Video surface when the path is running.
  final VideoSurface? surface;

  @override
  bool operator ==(Object other) =>
      other is VideoPathSnapshot &&
      other.generation == generation &&
      other.muteVideo == muteVideo &&
      other.cameraOff == cameraOff &&
      other.processor == processor &&
      other.surface == surface;

  @override
  int get hashCode =>
      Object.hash(generation, muteVideo, cameraOff, processor, surface);
}

/// Observes one Session Production video path.
///
/// A Transport plugin or disk package implements this and binds natively
/// via `attachProductionVideoPathNative`. Frames do not copy through Dart.
/// Camera preview has no Video sink seam.
abstract interface class VideoSink {
  /// Called on attach and whenever generation, Mute-video, Camera-off,
  /// processor identity, or the Video surface changes.
  void onVideoPath(VideoPathSnapshot snapshot);
}
