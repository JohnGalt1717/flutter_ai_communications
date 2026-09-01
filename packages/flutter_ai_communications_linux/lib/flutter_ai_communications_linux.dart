import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:logging/logging.dart';

import 'src/audio_backend.dart';
import 'src/audio_factory.dart';
import 'src/camera_backend.dart';
import 'src/camera_channel.dart';
import 'src/linux_bluetooth_identity.dart';

/// Linux adapter. Isolation is unavailable. Pulse / PipeWire via Dart FFI.
///
/// Camera uses a MethodChannel native graph (V4L2 → Texture).
final class FlutterAiCommunicationsLinux
    extends FlutterAiCommunicationsPlatform {
  /// Creates the Linux adapter.
  FlutterAiCommunicationsLinux({
    AudioBackend? backend,
    BluetoothIdentitySource? bluetooth,
    CameraBackend? camera,
  }) : _backend = backend ?? createAudioBackend(),
       _bluetooth = bluetooth ?? createBluetoothIdentitySource(),
       _camera = camera ?? MethodChannelCameraBackend();

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsLinux();
  }

  static final _log = Logger('FlutterAiCommunicationsLinux');

  final AudioBackend _backend;
  final BluetoothIdentitySource _bluetooth;
  final CameraBackend _camera;
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
  Timer? _catalogWatch;
  var _catalogListeners = 0;
  var _running = false;
  var _generation = 0;

  @override
  String get platformName => 'linux';

  @override
  IsolationEvent get lastIsolation => _lastIsolation;

  @override
  PairingSnapshot get lastObservedRoute => _observed;

  @override
  Stream<OsRouteChange> get osRouteChanges => _routes.stream;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async {
    unawaited(_prepareBluetoothCatalog());
    return _catalogUntilReady();
  }

  @override
  Stream<List<Endpoint>> get endpointCatalog async* {
    _catalogListeners++;
    _ensureCatalogWatch();
    try {
      yield _enrichedCatalog();
      unawaited(_prepareBluetoothCatalog());
      yield* _catalog.stream;
    } finally {
      _catalogListeners--;
      _maybeStopCatalogWatch();
    }
  }

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
      _path.add(const CoverageHint.ok());
      _emitObserved(force: true);
      _ensureCatalogWatch();
      _publishCatalog();
      unawaited(_prepareBluetoothCatalog());
    } else {
      _running = false;
      _emitObserved(force: true);
      _maybeStopCatalogWatch();
    }
    return started;
  }

  @override
  Future<void> stopNative() async {
    _running = false;
    _backend.stop();
    _observed = const PairingSnapshot();
    _maybeStopCatalogWatch();
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

  void _ensureCatalogWatch() {
    _catalogWatch ??= Timer.periodic(const Duration(seconds: 2), (_) {
      _publishCatalog();
    });
  }

  void _maybeStopCatalogWatch() {
    if (_running || _catalogListeners > 0) {
      return;
    }
    _catalogWatch?.cancel();
    _catalogWatch = null;
  }

  Future<void> _prepareBluetoothCatalog() async {
    try {
      await _bluetooth.prepare();
      _publishCatalog();
    } on Object catch (error, stack) {
      _log.fine('Bluetooth identity prepare failed', error, stack);
    }
  }

  List<Endpoint> _enrichedCatalog() {
    return mergeBluetoothIdentity(_backend.enumerate(), _bluetooth.current());
  }

  Future<List<Endpoint>> _catalogUntilReady() async {
    var catalog = _enrichedCatalog();
    for (var i = 0; i < 20 && catalog.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      catalog = _enrichedCatalog();
    }
    return catalog;
  }

  void _publishCatalog() {
    _catalog.add(_enrichedCatalog());
    if (_running) {
      _emitObserved();
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

  @override
  Future<List<CameraEndpoint>> enumerateCameras() => _camera.enumerate();

  @override
  Future<CameraPermission> requestCameraPermission() =>
      _camera.requestPermission();

  @override
  Future<NativeGraphStart> startCameraNative({
    String? cameraId,
    VideoFormat? videoFormat,
    bool enabled = true,
    bool muted = false,
  }) {
    return _camera.start(
      cameraId: cameraId,
      videoFormat: videoFormat,
      enabled: enabled,
      muted: muted,
    );
  }

  @override
  Future<void> stopCameraNative() => _camera.stop();

  @override
  Future<void> selectCameraNative(String cameraId) => _camera.select(cameraId);

  @override
  Future<void> setCameraEnabledNative(bool enabled) =>
      _camera.setEnabled(enabled);

  @override
  Future<void> setMuteVideoNative(bool muted) => _camera.setMuted(muted);

  @override
  VideoSurface? get lastVideoSurface => _camera.lastSurface;

  @override
  VideoFormat? get lastNativeVideoFormat => _camera.lastFormat;

  @override
  int get lastCameraFrameCount => _camera.frameCount;

  @override
  int get lastCameraLiveFrames => _camera.liveFrames;

  @override
  Future<void> pollCameraNative() => _camera.pollStats();
}
