import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host loopback Pair. Play bytes become capture bytes after the inner
/// adapter accepts them. Analog speaker → microphone is not this path.
final class LoopbackCommunicationsPlatform
    extends FlutterAiCommunicationsPlatform {
  /// Wraps a real (or fake) adapter and adds the loopback Pair.
  LoopbackCommunicationsPlatform(this.inner) {
    _innerCapture = inner.nativeCapture.listen(_onInnerCapture);
    _innerCatalog = inner.endpointCatalog.listen(
      _onInnerCatalog,
      onError: _catalog.addError,
    );
  }

  /// Capture Endpoint id.
  static const captureId = 'loopback-in';

  /// Render Endpoint id.
  static const renderId = 'loopback-out';

  /// Pair identity.
  static const pairId = 'loopback';

  /// Replaces the registered adapter with a loopback wrapper.
  static LoopbackCommunicationsPlatform wrapRegistered() {
    final current = FlutterAiCommunicationsPlatform.instance;
    if (current is LoopbackCommunicationsPlatform) {
      return current;
    }
    final wrapped = LoopbackCommunicationsPlatform(current);
    FlutterAiCommunicationsPlatform.instance = wrapped;
    return wrapped;
  }

  /// The real platform adapter.
  final FlutterAiCommunicationsPlatform inner;

  final StreamController<Uint8List> _capture =
      StreamController<Uint8List>.broadcast();
  final StreamController<List<Endpoint>> _catalog =
      StreamController<List<Endpoint>>.broadcast();
  StreamSubscription<Uint8List>? _innerCapture;
  StreamSubscription<List<Endpoint>>? _innerCatalog;
  var _running = false;
  var _paused = false;
  var _captureIsLoopback = false;
  String? _captureId;
  String? _renderId;

  static const List<Endpoint> loopbackPair = [
    Endpoint(
      id: captureId,
      name: 'Loopback',
      routeClass: RouteClass.wired,
      isCapture: true,
      pairId: pairId,
    ),
    Endpoint(
      id: renderId,
      name: 'Loopback',
      routeClass: RouteClass.wired,
      isCapture: false,
      pairId: pairId,
    ),
  ];

  @override
  String get platformName => inner.platformName;

  @override
  IsolationEvent get lastIsolation => inner.lastIsolation;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async => [
    ...await inner.enumerateEndpoints(),
    ...loopbackPair,
  ];

  @override
  Stream<List<Endpoint>> get endpointCatalog => _catalog.stream;

  @override
  Future<MicrophonePermission> requestMicrophonePermission() async {
    try {
      final permission = await inner.requestMicrophonePermission().timeout(
        const Duration(seconds: 2),
      );
      if (permission == MicrophonePermission.granted) {
        return permission;
      }
    } on Object {
      // Analog grant is optional for the host loopback Pair.
    }
    return MicrophonePermission.granted;
  }

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
  }) async {
    _captureId = captureId;
    _renderId = renderId;
    _captureIsLoopback = captureId == LoopbackCommunicationsPlatform.captureId;
    final innerCapture = captureId == LoopbackCommunicationsPlatform.captureId
        ? null
        : captureId;
    final innerRender = renderId == LoopbackCommunicationsPlatform.renderId
        ? null
        : renderId;
    NativeGraphStart started = NativeGraphStart.unavailable;
    try {
      started = await inner.startNative(
        captureId: innerCapture,
        renderId: innerRender,
      );
    } on Object {
      started = NativeGraphStart.failed;
    }
    if (started == NativeGraphStart.started || _captureIsLoopback) {
      _running = true;
      _paused = false;
      _catalog.add(await enumerateEndpoints());
      return NativeGraphStart.started;
    }
    return started;
  }

  @override
  Future<void> stopNative() async {
    _running = false;
    _paused = false;
    await inner.stopNative();
  }

  @override
  Future<void> pauseNative() async {
    _paused = true;
    await inner.pauseNative();
  }

  @override
  Future<void> resumeNative() async {
    await inner.resumeNative();
    _paused = false;
  }

  @override
  Stream<Uint8List> get nativeCapture => _capture.stream;

  @override
  Future<void> play(Uint8List bytes) {
    final accepted = inner.play(bytes);
    if (_running && !_paused && _captureIsLoopback) {
      _capture.add(Uint8List.fromList(bytes));
    }
    return accepted;
  }

  @override
  Future<void> selectEndpoints({String? captureId, String? renderId}) async {
    if (captureId != null) {
      _captureId = captureId;
      _captureIsLoopback =
          captureId == LoopbackCommunicationsPlatform.captureId;
    }
    if (renderId != null) {
      _renderId = renderId;
    }
    final innerCapture = _captureId == LoopbackCommunicationsPlatform.captureId
        ? null
        : _captureId;
    final innerRender = _renderId == LoopbackCommunicationsPlatform.renderId
        ? null
        : _renderId;
    await inner.selectEndpoints(captureId: innerCapture, renderId: innerRender);
  }

  @override
  Stream<IsolationEvent> get isolation => inner.isolation;

  @override
  Future<void> openIsolationSettings() => inner.openIsolationSettings();

  @override
  Future<void> flushPlayback() => inner.flushPlayback();

  @override
  Stream<CoverageHint> get pathCoverage => inner.pathCoverage;

  @override
  Stream<AudioFocusState> get audioFocus => inner.audioFocus;

  @override
  Stream<OsRouteChange> get osRouteChanges => inner.osRouteChanges;

  /// Releases the inner capture subscription.
  Future<void> dispose() async {
    await _innerCapture?.cancel();
    await _innerCatalog?.cancel();
    _innerCapture = null;
    _innerCatalog = null;
    await _capture.close();
    await _catalog.close();
  }

  void _onInnerCapture(Uint8List bytes) {
    if (_running && !_paused && !_captureIsLoopback) {
      _capture.add(bytes);
    }
  }

  void _onInnerCatalog(List<Endpoint> catalog) {
    _catalog.add([...catalog, ...loopbackPair]);
  }
}
