import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'src/audio_backend.dart';
import 'src/audio_factory.dart';

/// macOS adapter. Isolation is unavailable. Core Audio via Dart FFI.
final class FlutterAiCommunicationsMacos
    extends FlutterAiCommunicationsPlatform {
  /// Creates the macOS adapter.
  FlutterAiCommunicationsMacos({AudioBackend? backend})
    : _backend = backend ?? createAudioBackend();

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsMacos();
  }

  final AudioBackend _backend;
  final StreamController<IsolationEvent> _isolation =
      StreamController<IsolationEvent>.broadcast();
  final StreamController<List<Endpoint>> _catalog =
      StreamController<List<Endpoint>>.broadcast();
  final StreamController<CoverageHint> _path =
      StreamController<CoverageHint>.broadcast();
  final StreamController<OsRouteChange> _routes =
      StreamController<OsRouteChange>.broadcast();
  IsolationEvent _lastIsolation = const IsolationEvent(
    IsolationState.unavailable,
  );
  PairingSnapshot _observed = const PairingSnapshot();
  Timer? _catalogPoll;
  Timer? _observedPoll;
  var _running = false;
  var _generation = 0;

  @override
  String get platformName => 'macos';

  @override
  IsolationEvent get lastIsolation => _lastIsolation;

  @override
  PairingSnapshot get lastObservedRoute => _observed;

  @override
  Stream<OsRouteChange> get osRouteChanges => _routes.stream;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async => _backend.enumerate();

  @override
  Stream<List<Endpoint>> get endpointCatalog => _catalog.stream;

  @override
  Future<MicrophonePermission> requestMicrophonePermission() async =>
      _backend.probePermission();

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    bool noiseCancelling = true,
  }) async {
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
    final started = _backend.start(captureId: captureId, renderId: renderId);
    if (started == NativeGraphStart.started) {
      _running = true;
      _generation++;
      _catalog.add(_backend.enumerate());
      _path.add(const CoverageHint.ok());
      _emitObserved(force: true);
      _catalogPoll?.cancel();
      _catalogPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        _catalog.add(_backend.enumerate());
      });
      _observedPoll?.cancel();
      _observedPoll = Timer.periodic(const Duration(milliseconds: 250), (_) {
        _emitObserved();
      });
    }
    return started;
  }

  @override
  Future<void> stopNative() async {
    _catalogPoll?.cancel();
    _catalogPoll = null;
    _observedPoll?.cancel();
    _observedPoll = null;
    _running = false;
    _backend.stop();
  }

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
    if (_running) {
      _emitObserved(force: true);
    }
  }

  void _emitObserved({bool force = false}) {
    final next = _backend.observed;
    if (!force && next == _observed) {
      return;
    }
    _observed = next;
    _routes.add(
      OsRouteChange(
        captureId: _observed.captureId,
        renderId: _observed.renderId,
        generation: _generation,
      ),
    );
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
  Stream<CoverageHint> get pathCoverage => _path.stream;
}
