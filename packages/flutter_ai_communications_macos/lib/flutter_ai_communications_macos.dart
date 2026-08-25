import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'src/audio_backend.dart';
import 'src/macos_voice_processing_policy.dart';

/// macOS adapter.
///
/// Production uses one native duplex AVAudioEngine via MethodChannel (same
/// seam as iOS). Isolation is unavailable, so the Session raises the Sound
/// floor. Inject [backend] only in tests.
final class FlutterAiCommunicationsMacos
    extends FlutterAiCommunicationsPlatform {
  /// Creates the macOS adapter.
  ///
  /// When [backend] is omitted, production MethodChannel / native duplex is
  /// used. Tests inject a fake [AudioBackend].
  FlutterAiCommunicationsMacos({AudioBackend? backend})
    : _backend = backend,
      _channel = backend == null
          ? MethodChannelCommunicationsPlatform(platformName: 'macos')
          : null {
    assert(
      MacosVoiceProcessingPolicy.usesSingleDuplexEngine,
      'macOS must keep capture and playback on one duplex engine',
    );
  }

  /// Registers the production MethodChannel adapter.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsMacos();
  }

  final AudioBackend? _backend;
  final MethodChannelCommunicationsPlatform? _channel;
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
  IsolationEvent get lastIsolation => _channel?.lastIsolation ?? _lastIsolation;

  @override
  PairingSnapshot get lastObservedRoute =>
      _channel?.lastObservedRoute ?? _observed;

  @override
  NativeFormatReport get lastNativeFormats =>
      _channel?.lastNativeFormats ?? const NativeFormatReport();

  @override
  Stream<OsRouteChange> get osRouteChanges =>
      _channel?.osRouteChanges ?? _routes.stream;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async {
    final channel = _channel;
    if (channel != null) {
      return channel.enumerateEndpoints();
    }
    return _backend!.enumerate();
  }

  @override
  Stream<List<Endpoint>> get endpointCatalog {
    final channel = _channel;
    if (channel != null) {
      return channel.endpointCatalog;
    }
    return _catalog.stream;
  }

  @override
  Future<MicrophonePermission> requestMicrophonePermission() async {
    final channel = _channel;
    if (channel != null) {
      return channel.requestMicrophonePermission();
    }
    return _backend!.probePermission();
  }

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    bool noiseCancelling = true,
  }) async {
    final channel = _channel;
    if (channel != null) {
      return channel.startNative(
        captureId: captureId,
        renderId: renderId,
        captureFormat: captureFormat,
        playbackFormat: playbackFormat,
        noiseCancelling: noiseCancelling,
      );
    }

    // Isolation unavailable on macOS → Session raises Sound floor.
    final backend = _backend;
    if (backend == null) {
      return NativeGraphStart.failed;
    }
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
    final started = backend.start(
      captureId: captureId,
      renderId: renderId,
      noiseCancelling: noiseCancelling,
    );
    if (started == NativeGraphStart.started) {
      _running = true;
      _generation++;
      _catalog.add(backend.enumerate());
      _path.add(const CoverageHint.ok());
      _emitObserved(force: true);
      _catalogPoll?.cancel();
      _catalogPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        _catalog.add(backend.enumerate());
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
    final channel = _channel;
    if (channel != null) {
      return channel.stopNative();
    }
    _catalogPoll?.cancel();
    _catalogPoll = null;
    _observedPoll?.cancel();
    _observedPoll = null;
    _running = false;
    _backend!.stop();
  }

  @override
  Future<void> pauseNative() async {
    final channel = _channel;
    if (channel != null) {
      return channel.pauseNative();
    }
    _backend!.pause();
  }

  @override
  Future<void> resumeNative() async {
    final channel = _channel;
    if (channel != null) {
      return channel.resumeNative();
    }
    _backend!.resume();
  }

  @override
  Stream<Uint8List> get nativeCapture {
    final channel = _channel;
    if (channel != null) {
      return channel.nativeCapture;
    }
    return _backend!.capture;
  }

  @override
  Future<void> play(Uint8List bytes) async {
    final channel = _channel;
    if (channel != null) {
      return channel.play(bytes);
    }
    _backend!.play(bytes);
  }

  @override
  Future<void> selectEndpoints({String? captureId, String? renderId}) async {
    final channel = _channel;
    if (channel != null) {
      return channel.selectEndpoints(captureId: captureId, renderId: renderId);
    }
    _backend!.select(captureId: captureId, renderId: renderId);
    if (_running) {
      _emitObserved(force: true);
    }
  }

  void _emitObserved({bool force = false}) {
    final next = _backend!.observed;
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
  Stream<IsolationEvent> get isolation {
    final channel = _channel;
    if (channel != null) {
      return channel.isolation;
    }
    return _isolation.stream;
  }

  @override
  Future<void> openIsolationSettings() async {
    final channel = _channel;
    if (channel != null) {
      return channel.openIsolationSettings();
    }
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
  }

  @override
  Future<void> flushPlayback() async {
    final channel = _channel;
    if (channel != null) {
      return channel.flushPlayback();
    }
    _backend!.flush();
  }

  @override
  Stream<CoverageHint> get pathCoverage {
    final channel = _channel;
    if (channel != null) {
      return channel.pathCoverage;
    }
    return _path.stream;
  }

  @override
  Stream<AudioFocusState> get audioFocus {
    final channel = _channel;
    if (channel != null) {
      return channel.audioFocus;
    }
    return const Stream.empty();
  }
}
