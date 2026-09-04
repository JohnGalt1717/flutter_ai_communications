import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:logging/logging.dart';

import 'src/camera_backend.dart';
import 'src/camera_channel.dart';
import 'src/screen_channel.dart';
import 'src/wasapi_backend.dart';
import 'src/wasapi_factory.dart';
import 'src/windows_bluetooth_identity.dart';
import 'src/windows_camera_consent.dart';
import 'src/windows_microphone_consent.dart';
import 'src/windows_screen_consent.dart';

/// Windows adapter. Isolation is unavailable. WASAPI is called via Dart FFI.
///
/// Camera uses a MethodChannel native graph (Media Foundation → Texture).
final class FlutterAiCommunicationsWindows
    extends FlutterAiCommunicationsPlatform {
  /// Creates the Windows adapter.
  FlutterAiCommunicationsWindows({
    WasapiBackend? backend,
    WindowsMicrophoneConsent? consent,
    BluetoothIdentitySource? bluetooth,
    CameraBackend? camera,
    WindowsCameraConsent? cameraConsent,
    MethodChannelScreenBackend? screen,
    WindowsScreenConsent? screenConsent,
  }) : _backend = backend ?? createWasapiBackend(),
       _consent = consent ?? createWindowsMicrophoneConsent(),
       _bluetooth = bluetooth ?? createBluetoothIdentitySource(),
       _camera = camera ?? MethodChannelCameraBackend(),
       _cameraConsent = cameraConsent ?? createWindowsCameraConsent(),
       _screen = screen ?? MethodChannelScreenBackend(),
       _screenConsent = screenConsent ?? createWindowsScreenConsent();

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsWindows();
  }

  static final _log = Logger('FlutterAiCommunicationsWindows');

  final WasapiBackend _backend;
  final WindowsMicrophoneConsent _consent;
  final BluetoothIdentitySource _bluetooth;
  final CameraBackend _camera;
  final WindowsCameraConsent _cameraConsent;
  final MethodChannelScreenBackend _screen;
  final WindowsScreenConsent _screenConsent;
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
  NativeFormatReport _lastNativeFormats = const NativeFormatReport();
  Timer? _catalogWatch;
  var _catalogListeners = 0;
  var _running = false;
  var _generation = 0;

  @override
  String get platformName => 'windows';

  @override
  IsolationEvent get lastIsolation => _lastIsolation;

  @override
  PairingSnapshot get lastObservedRoute => _observed;

  @override
  NativeFormatReport get lastNativeFormats => _lastNativeFormats;

  @override
  Stream<OsRouteChange> get osRouteChanges => _routes.stream;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async {
    unawaited(_prepareBluetoothCatalog());
    return _enrichedCatalog();
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
  Future<MicrophonePermission> requestMicrophonePermission() async {
    final consent = await _consent.request();
    if (consent != MicrophonePermission.granted) {
      return consent;
    }
    return _backend.probePermission();
  }

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
      _lastNativeFormats = _backend.nativeFormats;
      _path.add(const CoverageHint.ok());
      _emitObserved(force: true);
      _ensureCatalogWatch();
      _publishCatalog();
      unawaited(_prepareBluetoothCatalog());
    } else {
      _running = false;
      _lastNativeFormats = const NativeFormatReport();
      _emitObserved(force: true);
      _maybeStopCatalogWatch();
    }
    return started;
  }

  @override
  Future<void> stopNative() async {
    _running = false;
    _backend.stop();
    _lastNativeFormats = const NativeFormatReport();
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
      _lastNativeFormats = _backend.nativeFormats;
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
  Future<CameraPermission> requestCameraPermission() async {
    final consent = await _cameraConsent.request();
    if (consent != CameraPermission.granted) {
      return consent;
    }
    return _camera.requestPermission();
  }

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

  @override
  Future<List<ScreenSource>> enumerateScreenSources() => _screen.enumerate();

  @override
  Future<ScreenPermission> requestScreenPermission() async {
    final consent = await _screenConsent.request();
    if (consent != ScreenPermission.granted) {
      return consent;
    }
    return _screen.requestPermission();
  }

  @override
  Future<NativeGraphStart> beginScreenPickNative() => _screen.beginPick();

  @override
  Future<void> endScreenPickNative() => _screen.endPick();

  @override
  Future<void> indicateScreenSourceNative(String? sourceId) =>
      _screen.indicate(sourceId);

  @override
  VideoSurface? screenPreviewNative(String sourceId) =>
      _screen.previews[sourceId];

  @override
  Future<NativeGraphStart> startScreenShareNative({
    required String sourceId,
    bool includeSystemAudio = false,
    bool cursor = true,
    bool motion = false,
  }) {
    return _screen.start(
      sourceId: sourceId,
      includeSystemAudio: includeSystemAudio,
      cursor: cursor,
      motion: motion,
    );
  }

  @override
  Future<void> stopScreenShareNative() async {
    _backend.stopLoopback();
    await _screen.stop();
  }

  @override
  Future<bool> setIncludeSystemAudioNative(bool enabled) async {
    if (!enabled) {
      _backend.stopLoopback();
      return false;
    }
    return _backend.startLoopback();
  }

  @override
  Future<void> setScreenMotionNative(bool motion) => _screen.setMotion(motion);

  @override
  Future<void> setScreenCursorNative(bool cursor) => _screen.setCursor(cursor);

  @override
  VideoSurface? get lastScreenSurface => _screen.lastSurface;

  @override
  VideoFormat? get lastScreenNativeFormat => _screen.lastFormat;

  @override
  String? get lastScreenUnavailableReason => _screen.lastUnavailableReason;
}
