import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'camera_backend.dart';

/// MethodChannel camera graph. Audio stays on Pulse FFI.
final class MethodChannelCameraBackend implements CameraBackend {
  /// Creates a channel backend.
  MethodChannelCameraBackend({MethodChannel? methods})
    : _methods =
          methods ??
          const MethodChannel('flutter_ai_communications/methods');

  final MethodChannel _methods;
  VideoSurface? _lastSurface;
  VideoFormat? _lastFormat;
  var _frameCount = 0;
  var _liveFrames = 0;

  @override
  VideoSurface? get lastSurface => _lastSurface;

  @override
  VideoFormat? get lastFormat => _lastFormat;

  @override
  int get frameCount => _frameCount;

  @override
  int get liveFrames => _liveFrames;

  @override
  Future<List<CameraEndpoint>> enumerate() async {
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>('enumerateCameras');
      return _readCameras(raw);
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<CameraPermission> requestPermission() async {
    try {
      final value = await _methods.invokeMethod<String>(
        'requestCameraPermission',
      );
      return switch (value) {
        'denied' => CameraPermission.denied,
        'restricted' => CameraPermission.restricted,
        _ => CameraPermission.granted,
      };
    } on MissingPluginException {
      return CameraPermission.denied;
    }
  }

  @override
  Future<NativeGraphStart> start({
    String? cameraId,
    VideoFormat? videoFormat,
    bool enabled = true,
    bool muted = false,
  }) async {
    try {
      final value = await _methods.invokeMethod<Object?>('startCameraNative', {
        'cameraId': cameraId,
        'width': videoFormat?.width ?? VideoFormat.defaultFormat.width,
        'height': videoFormat?.height ?? VideoFormat.defaultFormat.height,
        'frameRate':
            videoFormat?.frameRate ?? VideoFormat.defaultFormat.frameRate,
        'enabled': enabled,
        'muted': muted,
      });
      if (value is Map) {
        final status = value['status'] as String? ?? 'started';
        if (status != 'started') {
          _lastSurface = null;
          _lastFormat = null;
          return NativeGraphStart.unavailable;
        }
        final handle = _readInt(value['textureId']) ?? _readInt(value['handle']);
        _lastSurface = handle == null ? null : VideoSurface(handle: handle);
        final width = _readInt(value['width']);
        final height = _readInt(value['height']);
        final frameRate = _readInt(value['frameRate']);
        _lastFormat = width != null && height != null
            ? VideoFormat(
                width: width,
                height: height,
                frameRate: frameRate ?? 30,
              )
            : videoFormat ?? VideoFormat.defaultFormat;
        return NativeGraphStart.started;
      }
      _lastSurface = null;
      _lastFormat = null;
      return NativeGraphStart.unavailable;
    } on MissingPluginException {
      _lastSurface = null;
      _lastFormat = null;
      return NativeGraphStart.unavailable;
    }
  }

  @override
  Future<void> stop() async {
    _lastSurface = null;
    _lastFormat = null;
    try {
      await _methods.invokeMethod<void>('stopCameraNative');
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> select(String cameraId) async {
    try {
      await _methods.invokeMethod<void>('selectCameraNative', {
        'cameraId': cameraId,
      });
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await _methods.invokeMethod<void>('setCameraEnabledNative', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    try {
      await _methods.invokeMethod<void>('setMuteVideoNative', {'muted': muted});
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> pollStats() async {
    try {
      final value = await _methods.invokeMethod<Object?>('cameraGraphStats');
      if (value is Map) {
        _frameCount = _readInt(value['frameCount']) ?? 0;
        _liveFrames = _readInt(value['liveFrames']) ?? 0;
      }
    } on MissingPluginException {
      _frameCount = 0;
      _liveFrames = 0;
    }
  }

  List<CameraEndpoint> _readCameras(List<dynamic>? raw) {
    if (raw == null) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map)
          CameraEndpoint(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '',
            facing: switch (item['facing'] as String?) {
              'user' => CameraFacing.user,
              'environment' => CameraFacing.environment,
              'external' => CameraFacing.external,
              _ => CameraFacing.unspecified,
            },
            modes: [
              for (final mode in item['modes'] as List<dynamic>? ?? const [])
                if (mode is Map)
                  VideoFormat(
                    width: _readInt(mode['width']) ?? 0,
                    height: _readInt(mode['height']) ?? 0,
                    frameRate: _readInt(mode['frameRate']) ?? 30,
                  ),
            ],
          ),
    ];
  }

  int? _readInt(Object? value) => switch (value) {
    int n => n,
    num n => n.toInt(),
    _ => null,
  };
}
