part of '../flutter_ai_communications.dart';

/// Live duplex communications context.
///
/// Owns capture, render, mute, pause, ephemeral Endpoint/floor picks, and
/// Isolation / Coverage streams. Native reset must not replace these streams.
final class Session {
  Session._({
    required FlutterAiCommunicationsPlatform platform,
    required this.captureFormat,
    required this.playbackFormat,
    required this.preference,
    required this.bargeInPolicy,
    required CoverageSource coverageSource,
    required this._pairing,
    required List<Endpoint> catalog,
    required this._onStopped,
    required this._logger,
  }) : _platform = platform,
       _catalog = List<Endpoint>.of(catalog),
       _floor = SoundFloor(fixed: preference.soundFloor),
       _bargeIn = BargeIn(),
       _captureController = StreamController<Uint8List>.broadcast(),
       _isolationController = StreamController<IsolationEvent>.broadcast(),
       _coverageController = StreamController<Coverage>.broadcast() {
    capture = _captureController.stream;
    isolation = _isolationController.stream;
    coverage = _coverageController.stream;
    _captureSub = platform.nativeCapture.listen(
      _onNativeCapture,
      onError: _captureController.addError,
    );
    _isolationSub = platform.isolation.listen(
      _onIsolation,
      onError: _isolationController.addError,
    );
    _coverageSub = coverageSource.coverage.listen(
      _onHostCoverage,
      onError: _coverageController.addError,
    );
    _catalogSub = platform.endpointCatalog.listen(_onCatalog);
    _pathSub = platform.pathCoverage.listen(_onPathCoverage);
    _focusSub = platform.audioFocus.listen(_onAudioFocus);
    _routeSub = platform.osRouteChanges.listen(_onOsRoute);
    _onIsolation(platform.lastIsolation);
  }

  static const _pairer = EndpointPairer();

  final FlutterAiCommunicationsPlatform _platform;
  final void Function() _onStopped;
  final Logger _logger;
  final SoundFloor _floor;
  final BargeIn _bargeIn;
  final StreamController<Uint8List> _captureController;
  final StreamController<IsolationEvent> _isolationController;
  final StreamController<Coverage> _coverageController;

  StreamSubscription<Uint8List>? _captureSub;
  StreamSubscription<IsolationEvent>? _isolationSub;
  StreamSubscription<Coverage>? _coverageSub;
  StreamSubscription<List<Endpoint>>? _catalogSub;
  StreamSubscription<CoverageHint>? _pathSub;
  StreamSubscription<AudioFocusState>? _focusSub;
  StreamSubscription<OsRouteChange>? _routeSub;

  var _muted = false;
  var _paused = false;
  var _stopped = false;
  var _coverageParked = false;
  var _isolationMissing = false;
  IsolationEvent _lastIsolation = const IsolationEvent(IsolationState.unknown);
  PairingSnapshot _pairing;
  List<Endpoint> _catalog;
  Coverage _hostCoverage = const Coverage.ok();
  Coverage _pathCoverage = const Coverage.ok();

  /// Capture-out Format. Defaults to PCM16 LE mono 24 kHz.
  final AudioFormat captureFormat;

  /// Playback-in Format. May differ from [captureFormat].
  final AudioFormat playbackFormat;

  /// Preference the host passed to [AudioManager.start]. Never rewritten.
  final SessionPreference preference;

  /// Whether barge-in is local or left to remote VAD.
  final BargeInPolicy bargeInPolicy;

  /// Floor-applied capture bytes. Mute emits silence on this same stream.
  late final Stream<Uint8List> capture;

  /// Isolation signals. Host owns every prompt string.
  late final Stream<IsolationEvent> isolation;

  /// Combined audio-path and host Coverage.
  late final Stream<Coverage> coverage;

  /// Last Isolation event. Host UI can seed from this before listening.
  IsolationEvent get lastIsolation => _lastIsolation;

  /// Whether the user's voice is replaced with silence frames.
  bool get isMuted => _muted;

  /// Whether capture and playback are parked.
  bool get isPaused => _paused;

  /// Whether [stop] has ended this Session.
  bool get isStopped => _stopped;

  /// Current sound floor. Ephemeral picks do not write [preference].
  double? get soundFloor => _floor.fixed;

  /// Active pairing snapshot. Ephemeral; does not write [preference].
  PairingSnapshot get pairing => _pairing;

  /// Ephemeral capture Endpoint id, if the user overrode [preference].
  String? get selectedCaptureId => _pairing.captureId;

  /// Ephemeral render Endpoint id, if the user overrode [preference].
  String? get selectedRenderId => _pairing.renderId;

  /// Renders [bytes] in [playbackFormat]. No-op while paused or stopped.
  Future<void> play(Uint8List bytes) async {
    if (_stopped || _paused) {
      return;
    }
    _bargeIn.onPlay();
    await _platform.play(bytes);
  }

  /// Mute keeps the same capture subscription and emits silence frames.
  void mute() {
    if (_stopped) {
      return;
    }
    _muted = true;
    _logger.fine('session muted');
  }

  /// Restores voice frames on the same capture stream.
  void unmute() {
    if (_stopped) {
      return;
    }
    _muted = false;
    _logger.fine('session unmuted');
  }

  /// Parks capture and playback. The Session and its streams stay put.
  Future<void> pause() async {
    if (_stopped || _paused) {
      return;
    }
    _paused = true;
    _bargeIn.onIdle();
    await _platform.pauseNative();
    _logger.fine('session paused');
  }

  /// Resumes on the same Session and the same broadcast streams.
  Future<void> resume() async {
    if (_stopped || !_paused) {
      return;
    }
    await _platform.resumeNative();
    _paused = false;
    _logger.fine('session resumed');
  }

  /// Ephemeral Endpoint pick. Does not change [preference].
  Future<void> select({String? captureId, String? renderId}) async {
    if (_stopped) {
      return;
    }
    _pairing = _pairer.select(
      _pairing,
      _catalog,
      captureId: captureId,
      renderId: renderId,
    );
    await _platform.selectEndpoints(
      captureId: _pairing.captureId,
      renderId: _pairing.renderId,
    );
  }

  /// Ephemeral sound floor. `null` returns to adaptive. Does not write [preference].
  void setSoundFloor(double? value) {
    if (_stopped) {
      return;
    }
    _floor.setFloor(value);
  }

  /// Opens the system Isolation UI. Host still owns copy.
  Future<void> openIsolationSettings() => _platform.openIsolationSettings();

  /// Ends the Session. Streams stay open until this object is discarded.
  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    await _platform.stopNative();
    await _captureSub?.cancel();
    await _isolationSub?.cancel();
    await _coverageSub?.cancel();
    await _catalogSub?.cancel();
    await _pathSub?.cancel();
    await _focusSub?.cancel();
    await _routeSub?.cancel();
    await _captureController.close();
    await _isolationController.close();
    await _coverageController.close();
    _onStopped();
    _logger.fine('session stopped');
  }

  void _onNativeCapture(Uint8List bytes) {
    if (_stopped || _paused) {
      return;
    }
    if (_muted) {
      _captureController.add(Uint8List(bytes.length));
      return;
    }
    final working = captureFormat.encoding == AudioEncoding.pcm16le
        ? bytes
        : const AudioTranscoder().toWorking(bytes, captureFormat);
    final rate = captureFormat.encoding == AudioEncoding.pcm16le
        ? captureFormat.sampleRate
        : AudioTranscoder.working.sampleRate;
    _bargeIn.remember(working, rate);
    if (bargeInPolicy == BargeInPolicy.local &&
        _bargeIn.playbackActive &&
        _bargeIn.isVoice(working, rate)) {
      unawaited(_flushBargeIn(rate));
    }
    final gated = _floor.apply(
      working,
      sampleRate: rate,
      routeClass: _selectedRouteClass(),
      isolationMissing: _isolationMissing,
    );
    final out = captureFormat.encoding == AudioEncoding.pcm16le
        ? gated
        : const AudioTranscoder().fromWorking(gated, captureFormat);
    _captureController.add(out);
  }

  Future<void> _flushBargeIn(int sampleRate) async {
    await _platform.flushPlayback();
    _bargeIn.onIdle();
    for (final frame in _bargeIn.takePreroll()) {
      final gated = _floor.apply(
        frame,
        sampleRate: sampleRate,
        routeClass: _selectedRouteClass(),
        isolationMissing: _isolationMissing,
      );
      if (gated.any((b) => b != 0)) {
        _captureController.add(
          captureFormat.encoding == AudioEncoding.pcm16le
              ? gated
              : const AudioTranscoder().fromWorking(gated, captureFormat),
        );
      }
    }
  }

  void _onIsolation(IsolationEvent event) {
    _lastIsolation = event;
    _isolationMissing =
        event.state == IsolationState.off ||
        event.state == IsolationState.unavailable;
    _isolationController.add(event);
  }

  void _onHostCoverage(Coverage next) {
    _hostCoverage = next;
    _emitCoverage();
  }

  void _onPathCoverage(CoverageHint hint) {
    _pathCoverage = hint.alive
        ? const Coverage.ok()
        : Coverage.lost(
            reason: hint.reason == 'airplane'
                ? CoverageReason.airplane
                : CoverageReason.pathDead,
          );
    _emitCoverage();
  }

  void _emitCoverage() {
    final next = _pathCoverage.level == CoverageLevel.lost
        ? _pathCoverage
        : _hostCoverage;
    _coverageController.add(next);
    if (next.level == CoverageLevel.lost && !_stopped) {
      _coverageParked = true;
      unawaited(pause());
    } else if (next.level == CoverageLevel.ok &&
        _coverageParked &&
        !_stopped) {
      _coverageParked = false;
      unawaited(resume());
    }
  }

  void _onAudioFocus(AudioFocusState state) {
    if (state == AudioFocusState.interrupted) {
      unawaited(pause());
    }
  }

  void _onCatalog(List<Endpoint> catalog) {
    _catalog = List<Endpoint>.of(catalog);
    final next = _pairer.onCatalogChanged(_pairing, _catalog);
    if (next != _pairing) {
      _pairing = next;
      unawaited(
        _platform.selectEndpoints(
          captureId: _pairing.captureId,
          renderId: _pairing.renderId,
        ),
      );
    }
  }

  void _onOsRoute(OsRouteChange change) {
    _pairing = _pairer.onOsForced(
      _catalog,
      captureId: change.captureId,
      renderId: change.renderId,
    );
    unawaited(
      _platform.selectEndpoints(
        captureId: _pairing.captureId,
        renderId: _pairing.renderId,
      ),
    );
  }

  RouteClass? _selectedRouteClass() {
    final id = _pairing.captureId;
    return _catalog.where((e) => e.id == id).firstOrNull?.routeClass;
  }
}
