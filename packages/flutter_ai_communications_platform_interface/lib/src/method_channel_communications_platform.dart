import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'flutter_ai_communications_platform.dart';
import 'isolation.dart';
import 'microphone_permission.dart';
import 'native_graph_start.dart';
import 'platform_events.dart';

/// Method/EventChannel adapter shared by iOS and Android.
///
/// Capture, Isolation, Coverage, focus, and OS-route events land on
/// broadcast controllers that survive native teardown (ADR-0004).
class MethodChannelCommunicationsPlatform
    extends FlutterAiCommunicationsPlatform {
  /// Creates a channel adapter.
  MethodChannelCommunicationsPlatform({
    required this.platformName,
    MethodChannel? methodChannel,
    EventChannel? captureChannel,
    EventChannel? eventsChannel,
  }) : _methods =
           methodChannel ??
           const MethodChannel('flutter_ai_communications/methods'),
       _capture =
           captureChannel ??
           const EventChannel('flutter_ai_communications/capture'),
       _events =
           eventsChannel ??
           const EventChannel('flutter_ai_communications/events') {
    nativeCapture = _captureOut.stream;
    _captureSub = _capture.receiveBroadcastStream().listen(_onCaptureEvent);
    _eventsSub = _events.receiveBroadcastStream().listen(_onControlEvent);
  }

  /// Federated adapter name.
  @override
  final String platformName;

  final MethodChannel _methods;
  final EventChannel _capture;
  final EventChannel _events;

  final StreamController<Uint8List> _captureOut =
      StreamController<Uint8List>.broadcast();
  final StreamController<List<Endpoint>> _catalogOut =
      StreamController<List<Endpoint>>.broadcast();
  final StreamController<IsolationEvent> _isolationOut =
      StreamController<IsolationEvent>.broadcast();
  final StreamController<CoverageHint> _pathOut =
      StreamController<CoverageHint>.broadcast();
  final StreamController<AudioFocusState> _focusOut =
      StreamController<AudioFocusState>.broadcast();
  final StreamController<OsRouteChange> _routeOut =
      StreamController<OsRouteChange>.broadcast();

  StreamSubscription<dynamic>? _captureSub;
  StreamSubscription<dynamic>? _eventsSub;
  IsolationEvent _lastIsolation = const IsolationEvent(IsolationState.unknown);

  @override
  IsolationEvent get lastIsolation => _lastIsolation;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async {
    final raw = await _methods.invokeMethod<List<dynamic>>(
      'enumerateEndpoints',
    );
    return _readEndpoints(raw);
  }

  @override
  Stream<List<Endpoint>> get endpointCatalog => _catalogOut.stream;

  @override
  Future<MicrophonePermission> requestMicrophonePermission() async {
    final value = await _methods.invokeMethod<String>(
      'requestMicrophonePermission',
    );
    return switch (value) {
      'denied' => MicrophonePermission.denied,
      'restricted' => MicrophonePermission.restricted,
      _ => MicrophonePermission.granted,
    };
  }

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
  }) async {
    final value = await _methods.invokeMethod<String>('startNative', {
      'captureId': captureId,
      'renderId': renderId,
    });
    return switch (value) {
      'unavailable' => NativeGraphStart.unavailable,
      'failed' => NativeGraphStart.failed,
      _ => NativeGraphStart.started,
    };
  }

  @override
  Future<void> stopNative() => _methods.invokeMethod<void>('stopNative');

  @override
  Future<void> pauseNative() => _methods.invokeMethod<void>('pauseNative');

  @override
  Future<void> resumeNative() => _methods.invokeMethod<void>('resumeNative');

  @override
  late final Stream<Uint8List> nativeCapture;

  @override
  Future<void> play(Uint8List bytes) =>
      _methods.invokeMethod<void>('play', bytes);

  @override
  Future<void> selectEndpoints({String? captureId, String? renderId}) =>
      _methods.invokeMethod<void>('selectEndpoints', {
        'captureId': captureId,
        'renderId': renderId,
      });

  @override
  Stream<IsolationEvent> get isolation => _isolationOut.stream;

  @override
  Future<void> openIsolationSettings() =>
      _methods.invokeMethod<void>('openIsolationSettings');

  @override
  Future<void> flushPlayback() => _methods.invokeMethod<void>('flushPlayback');

  @override
  Stream<CoverageHint> get pathCoverage => _pathOut.stream;

  @override
  Stream<AudioFocusState> get audioFocus => _focusOut.stream;

  @override
  Stream<OsRouteChange> get osRouteChanges => _routeOut.stream;

  void _onCaptureEvent(dynamic event) {
    if (event is Uint8List) {
      _captureOut.add(event);
    } else if (event is ByteData) {
      _captureOut.add(event.buffer.asUint8List());
    }
  }

  void _onControlEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    final type = event['type'] as String?;
    final payload = event['payload'];
    switch (type) {
      case 'catalog':
        _catalogOut.add(_readEndpoints(payload as List<dynamic>?));
      case 'isolation':
        _lastIsolation = IsolationEvent(
          _isolationState(payload as String? ?? 'unknown'),
        );
        _isolationOut.add(_lastIsolation);
      case 'path':
        if (payload is Map) {
          final alive = payload['alive'] == true;
          _pathOut.add(
            CoverageHint(alive: alive, reason: payload['reason'] as String?),
          );
        }
      case 'focus':
        _focusOut.add(
          payload == 'interrupted'
              ? AudioFocusState.interrupted
              : AudioFocusState.active,
        );
      case 'route':
        if (payload is Map) {
          _routeOut.add(
            OsRouteChange(
              captureId: payload['captureId'] as String?,
              renderId: payload['renderId'] as String?,
            ),
          );
        }
    }
  }

  List<Endpoint> _readEndpoints(List<dynamic>? raw) {
    if (raw == null) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (map) => Endpoint(
            id: map['id'] as String,
            name: map['name'] as String,
            routeClass: _routeClass(map['routeClass'] as String?),
            isCapture: map['isCapture'] == true,
            pairId: map['pairId'] as String?,
          ),
        )
        .toList();
  }

  RouteClass _routeClass(String? name) => switch (name) {
    'handset' => RouteClass.handset,
    'speakerphone' => RouteClass.speakerphone,
    'bluetooth' => RouteClass.bluetooth,
    'wired' => RouteClass.wired,
    'car' => RouteClass.car,
    _ => RouteClass.speakerphone,
  };

  IsolationState _isolationState(String name) => switch (name) {
    'on' => IsolationState.on,
    'off' => IsolationState.off,
    'unavailable' => IsolationState.unavailable,
    _ => IsolationState.unknown,
  };

  /// Cancels channel subscriptions. Tests only.
  Future<void> dispose() async {
    await _captureSub?.cancel();
    await _eventsSub?.cancel();
    await _captureOut.close();
    await _catalogOut.close();
    await _isolationOut.close();
    await _pathOut.close();
    await _focusOut.close();
    await _routeOut.close();
  }
}
