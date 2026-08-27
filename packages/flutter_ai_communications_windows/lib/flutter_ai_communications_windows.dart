import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'src/wasapi_backend.dart';
import 'src/wasapi_factory.dart';
import 'src/windows_bluetooth_identity.dart';
import 'src/windows_microphone_consent.dart';

/// Windows adapter. Isolation is unavailable. WASAPI is called via Dart FFI.
final class FlutterAiCommunicationsWindows
    extends FlutterAiCommunicationsPlatform {
  /// Creates the Windows adapter.
  FlutterAiCommunicationsWindows({
    WasapiBackend? backend,
    WindowsMicrophoneConsent? consent,
    BluetoothIdentitySource? bluetooth,
  }) : _backend = backend ?? createWasapiBackend(),
       _consent = consent ?? createWindowsMicrophoneConsent(),
       _bluetooth = bluetooth ?? createBluetoothIdentitySource();

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsWindows();
  }

  final WasapiBackend _backend;
  final WindowsMicrophoneConsent _consent;
  final BluetoothIdentitySource _bluetooth;
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
    await _bluetooth.prepare();
    _publishCatalog();
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
}
