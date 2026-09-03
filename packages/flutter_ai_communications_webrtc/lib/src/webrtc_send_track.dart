import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Outbound video handle a host addTracks on its own PeerConnection.
///
/// Not a PeerConnection and not a MediaStream. Null on the sink while
/// Camera-off. Mute-video keeps this handle.
final class WebrtcSendTrack {
  /// Creates a Send track snapshot.
  const WebrtcSendTrack({
    required this.id,
    required this.generation,
    required this.muteVideo,
    required this.processor,
    this.surface,
  });

  /// Stable for one Production video path generation.
  final String id;

  /// Production video path generation.
  final int generation;

  /// Mute-video: black frames, graph stays up.
  final bool muteVideo;

  /// Selected Video processor. v1 is [NoneVideoProcessor].
  final VideoProcessor processor;

  /// Local send Video surface while the path is running.
  final VideoSurface? surface;

  @override
  bool operator ==(Object other) =>
      other is WebrtcSendTrack &&
      other.id == id &&
      other.generation == generation &&
      other.muteVideo == muteVideo &&
      other.processor == processor &&
      other.surface == surface;

  @override
  int get hashCode =>
      Object.hash(id, generation, muteVideo, processor, surface);
}
