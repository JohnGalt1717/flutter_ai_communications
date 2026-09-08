part of '../flutter_ai_communications.dart';

/// Video-only local graph for in-call camera settings. Not a Session.
final class CameraPreview {
  CameraPreview._({
    required FlutterAiCommunicationsPlatform platform,
    required this.surface,
    required String cameraId,
    required void Function() onStopped,
    VideoProcessor videoProcessor = const NoneVideoProcessor(),
  }) : _platform = platform,
       _cameraId = cameraId,
       _onStopped = onStopped,
       _videoProcessor = videoProcessor;

  final FlutterAiCommunicationsPlatform _platform;
  final void Function() _onStopped;
  var _stopped = false;
  String _cameraId;
  VideoProcessor _videoProcessor;

  /// Local Video surface.
  final VideoSurface surface;

  /// Current camera id.
  String get selectedCameraId => _cameraId;

  /// Selected Video processor on this preview graph.
  VideoProcessor get videoProcessor => _videoProcessor;

  /// Selects a Video processor without restarting the preview graph.
  Future<ProcessorSetResult> setVideoProcessor(VideoProcessor processor) async {
    if (_stopped) {
      return const ProcessorInvalid();
    }
    if (processor is BlurVideoProcessor && !processor.isValid) {
      return const ProcessorInvalid();
    }
    if (processor is ReplaceVideoProcessor && !processor.isValid) {
      return const ProcessorInvalid();
    }
    final native = await _platform.setVideoProcessorNative(processor);
    switch (native) {
      case NativeProcessorResult.invalid:
        return const ProcessorInvalid();
      case NativeProcessorResult.unavailable:
        _videoProcessor = const NoneVideoProcessor();
        return const ProcessorUnavailable();
      case NativeProcessorResult.ready:
        _videoProcessor = processor;
        return ProcessorReady(processor);
    }
  }

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
