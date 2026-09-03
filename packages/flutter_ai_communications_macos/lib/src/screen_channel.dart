import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// MethodChannel screen graph used by the macOS adapter.
final class MethodChannelScreenBackend {
  /// Creates a channel backend.
  MethodChannelScreenBackend({MethodChannel? methods})
    : _methods =
          methods ?? const MethodChannel('flutter_ai_communications/methods');

  final MethodChannel _methods;
  VideoSurface? lastSurface;
  VideoFormat? lastFormat;
  String? lastUnavailableReason;
  final Map<String, VideoSurface> previews = {};

  Future<List<ScreenSource>> enumerate() async {
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>(
        'enumerateScreenSources',
      );
      return _readSources(raw);
    } on MissingPluginException {
      return const [];
    }
  }

  Future<ScreenPermission> requestPermission() async {
    try {
      final value = await _methods.invokeMethod<String>(
        'requestScreenPermission',
      );
      return switch (value) {
        'denied' => ScreenPermission.denied,
        'restricted' => ScreenPermission.restricted,
        _ => ScreenPermission.granted,
      };
    } on MissingPluginException {
      return ScreenPermission.denied;
    }
  }

  Future<NativeGraphStart> beginPick() async {
    try {
      final value = await _methods.invokeMethod<Object?>(
        'beginScreenPickNative',
      );
      previews
        ..clear()
        ..addAll(_readPreviews(value));
      return previews.isEmpty
          ? NativeGraphStart.unavailable
          : NativeGraphStart.started;
    } on MissingPluginException {
      previews.clear();
      return NativeGraphStart.unavailable;
    }
  }

  Future<void> endPick() async {
    previews.clear();
    try {
      await _methods.invokeMethod<void>('endScreenPickNative');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> indicate(String? sourceId) async {
    try {
      await _methods.invokeMethod<void>('indicateScreenSourceNative', {
        'sourceId': sourceId,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<NativeGraphStart> start({
    required String sourceId,
    bool includeSystemAudio = false,
    bool cursor = true,
    bool motion = false,
  }) async {
    try {
      final value = await _methods
          .invokeMethod<Object?>('startScreenShareNative', {
            'sourceId': sourceId,
            'includeSystemAudio': includeSystemAudio,
            'cursor': cursor,
            'motion': motion,
          });
      if (value is Map) {
        final status = value['status'] as String? ?? 'started';
        if (status != 'started') {
          lastSurface = null;
          lastFormat = null;
          lastUnavailableReason = value['reason'] as String? ?? status;
          return status == 'failed'
              ? NativeGraphStart.failed
              : NativeGraphStart.unavailable;
        }
        final handle = value['textureId'] as int? ?? value['handle'] as int?;
        lastSurface = handle == null ? null : VideoSurface(handle: handle);
        final width = value['width'] as int?;
        final height = value['height'] as int?;
        final frameRate = value['frameRate'] as int?;
        lastFormat = width != null && height != null
            ? VideoFormat(
                width: width,
                height: height,
                frameRate: frameRate ?? 5,
              )
            : null;
        lastUnavailableReason = null;
        return NativeGraphStart.started;
      }
      lastSurface = null;
      lastFormat = null;
      lastUnavailableReason = 'none';
      return NativeGraphStart.unavailable;
    } on MissingPluginException {
      lastSurface = null;
      lastFormat = null;
      lastUnavailableReason = 'none';
      return NativeGraphStart.unavailable;
    }
  }

  Future<void> stop() async {
    lastSurface = null;
    lastFormat = null;
    try {
      await _methods.invokeMethod<void>('stopScreenShareNative');
    } on MissingPluginException {
      return;
    }
  }

  Future<bool> setIncludeSystemAudio(bool enabled) async {
    try {
      return await _methods.invokeMethod<bool>('setIncludeSystemAudioNative', {
            'enabled': enabled,
          }) ==
          true;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> setMotion(bool motion) async {
    try {
      await _methods.invokeMethod<void>('setScreenMotionNative', {
        'motion': motion,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> setCursor(bool cursor) async {
    try {
      await _methods.invokeMethod<void>('setScreenCursorNative', {
        'cursor': cursor,
      });
    } on MissingPluginException {
      return;
    }
  }

  Map<String, VideoSurface> _readPreviews(Object? value) {
    if (value is! Map) {
      return {};
    }
    final raw = value['previews'] ?? value;
    if (raw is! Map) {
      return {};
    }
    final out = <String, VideoSurface>{};
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value is int) {
        out[entry.key as String] = VideoSurface(handle: entry.value as int);
      }
    }
    return out;
  }

  List<ScreenSource> _readSources(List<dynamic>? raw) {
    if (raw == null) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map)
          ScreenSource(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '',
            kind: switch (item['kind'] as String?) {
              'window' => ScreenSourceKind.window,
              'allDisplays' => ScreenSourceKind.allDisplays,
              'systemPicker' => ScreenSourceKind.systemPicker,
              _ => ScreenSourceKind.display,
            },
            x: item['x'] as int?,
            y: item['y'] as int?,
            width: item['width'] as int?,
            height: item['height'] as int?,
            canPreview: item['canPreview'] == true,
          ),
    ];
  }
}
