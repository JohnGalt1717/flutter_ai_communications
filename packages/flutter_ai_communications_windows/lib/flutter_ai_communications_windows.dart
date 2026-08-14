import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'src/wasapi_backend.dart';
import 'src/wasapi_factory.dart';

/// Windows adapter. Isolation is unavailable. WASAPI is called via Dart FFI.
final class FlutterAiCommunicationsWindows
    extends FlutterAiCommunicationsPlatform {
  /// Creates the Windows adapter.
  FlutterAiCommunicationsWindows({WasapiBackend? backend})
    : _backend = backend ?? createWasapiBackend();

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsWindows();
  }

  final WasapiBackend _backend;
  final StreamController<IsolationEvent> _isolation =
      StreamController<IsolationEvent>.broadcast();
  IsolationEvent _lastIsolation = const IsolationEvent(
    IsolationState.unavailable,
  );

  @override
  String get platformName => 'windows';

  @override
  IsolationEvent get lastIsolation => _lastIsolation;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async => _backend.enumerate();

  @override
  Stream<List<Endpoint>> get endpointCatalog => _backend.catalog;

  @override
  Future<MicrophonePermission> requestMicrophonePermission() async {
    try {
      if (_backend.enumerate().any((endpoint) => endpoint.isCapture)) {
        return MicrophonePermission.granted;
      }
      final started = _backend.start();
      _backend.stop();
      return started == NativeGraphStart.started
          ? MicrophonePermission.granted
          : MicrophonePermission.denied;
    } on Object {
      return MicrophonePermission.denied;
    }
  }

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
  }) async {
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
    return _backend.start(captureId: captureId, renderId: renderId);
  }

  @override
  Future<void> stopNative() async => _backend.stop();

  @override
  Future<void> pauseNative() async => _backend.pause();

  @override
  Future<void> resumeNative() async => _backend.resume();

  @override
  Stream<Uint8List> get nativeCapture => _backend.capture;

  @override
  Future<void> play(Uint8List bytes) async => _backend.play(bytes);

  @override
  Future<void> selectEndpoints({String? captureId, String? renderId}) async {
    _backend.select(captureId: captureId, renderId: renderId);
  }

  @override
  Stream<IsolationEvent> get isolation => _isolation.stream;

  @override
  Future<void> openIsolationSettings() async {
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
  }

  @override
  Future<void> flushPlayback() async => _backend.flush();

  @override
  Stream<CoverageHint> get pathCoverage => _backend.path;

  @override
  Stream<OsRouteChange> get osRouteChanges => _backend.routes;
}
