import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Native camera graph used by the Linux adapter.
abstract class CameraBackend {
  /// Snapshot of Camera Endpoints.
  Future<List<CameraEndpoint>> enumerate();

  /// Device-node or portal access. Must not leave a graph running.
  Future<CameraPermission> requestPermission();

  /// Starts the Production video path. Missing camera is [NativeGraphStart.unavailable].
  Future<NativeGraphStart> start({
    String? cameraId,
    VideoFormat? videoFormat,
    bool enabled = true,
    bool muted = false,
  });

  /// Tears down capture. Does not end the Session.
  Future<void> stop();

  /// Ephemeral camera pick. Must not persist Camera preference.
  Future<void> select(String cameraId);

  /// Camera-off when [enabled] is false; hardware may stop.
  Future<void> setEnabled(bool enabled);

  /// Mute-video substitutes black frames; the graph stays up.
  Future<void> setMuted(bool muted);

  /// Last Video surface from camera start, if any.
  VideoSurface? get lastSurface;

  /// Negotiated Native Video Format from the last camera start.
  VideoFormat? get lastFormat;

  /// Native captured frames since the last camera start.
  int get frameCount;

  /// Frames that contained non-black pixels.
  int get liveFrames;

  /// Refreshes [frameCount] and [liveFrames] from native.
  Future<void> pollStats();
}
