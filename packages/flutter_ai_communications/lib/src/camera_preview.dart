part of '../flutter_ai_communications.dart';

/// Video-only local graph for in-call camera settings. Not a Session.
final class CameraPreview {
  CameraPreview._({
    required FlutterAiCommunicationsPlatform platform,
    required this.surface,
    required String cameraId,
    required void Function() onStopped,
  }) : _platform = platform,
       _cameraId = cameraId,
       _onStopped = onStopped;

  final FlutterAiCommunicationsPlatform _platform;
  final void Function() _onStopped;
  var _stopped = false;
  String _cameraId;

  /// Local Video surface.
  final VideoSurface surface;

  /// Current camera id.
  String get selectedCameraId => _cameraId;

  /// Switch camera in the preview. Does not change the Session send path.
  Future<void> selectCamera(String cameraId) async {
    if (_stopped) {
      return;
    }
    _cameraId = cameraId;
    await _platform.selectCameraNative(cameraId);
  }

  /// Stops the preview graph.
  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    await _platform.stopCameraNative();
    _onStopped();
  }
}
