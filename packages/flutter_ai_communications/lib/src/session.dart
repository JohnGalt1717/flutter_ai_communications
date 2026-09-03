part of '../flutter_ai_communications.dart';

/// Live capture-only, playback-only, or duplex communications context.
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
    required this.direction,
    required this.purpose,
    required CoverageSource coverageSource,
    required PairingSnapshot desired,
    required bool preferenceControlled,
    required this._endpoints,
    required List<Endpoint> catalog,
    required this._onStopped,
    required this._logger,
    NativeFormatReport? nativeFormats,
    this.cameraSend = false,
    this.videoFormat = VideoFormat.defaultFormat,
    this.cameraPreference = const CameraPreference(),
    this.videoProcessor = const NoneVideoProcessor(),
    String? cameraId,
    bool cameraEnabled = true,
    bool videoMuted = false,
    VideoSurface? videoSurface,
    VideoFormat? nativeVideoFormat,
    String? videoUnavailableReason,
  }) : _platform = platform,
       _catalog = List<Endpoint>.of(catalog),
       _desired = desired,
       _applied = desired,
       _observed = platform.lastObservedRoute,
       _preferenceControlled = preferenceControlled,
       _floor = SoundFloor(
         fixed: preference.soundFloor,
         processor: preference.processor,
       ),
       _bargeIn = BargeIn(),
       _playback = PlaybackTimeline(sampleRate: playbackFormat.sampleRate),
       _captureController = StreamController<Uint8List>.broadcast(),
       _isolationController = StreamController<IsolationEvent>.broadcast(),
       _coverageController = StreamController<Coverage>.broadcast(),
       _statusController = StreamController<SessionStatus>.broadcast(),
       _cameraId = cameraId,
       _cameraEnabled = cameraEnabled,
       _videoMuted = videoMuted,
       _videoSurface = videoSurface,
       _nativeVideoFormat = nativeVideoFormat,
       _videoUnavailableReason = videoUnavailableReason {
    capture = _captureController.stream;
    isolation = _isolationController.stream;
    coverage = _coverageController.stream;
    statuses = _statusController.stream;
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
    if (!preferenceControlled) {
      _explicitCaptureId = preference.captureId;
      _explicitRenderId = preference.renderId;
    }
    if (!direction.hasCapture) {
      _lifecycle = SessionLifecycle.live;
    }
    _adoptNativeFormats(nativeFormats ?? platform.lastNativeFormats);
    _adoptAcousticProfile();
    _log(PipelineLog.desired, _routeFields(_desired, cause: 'start'));
    _log(PipelineLog.applied, _routeFields(_applied, cause: 'start'));
    if (_observed.captureId != null || _observed.renderId != null) {
      _log(PipelineLog.observed, _routeFields(_observed, cause: 'start'));
    }
    _publishStatus(_computeStatus());
    _statusController.onListen = () {
      if (!_statusController.isClosed) {
        _statusController.add(_status);
      }
    };
  }

  static const _resolver = PreferenceResolver();

  /// Missing-frame timeout for an active unpaused capture Session.
  static Duration stallTimeout = const Duration(seconds: 2);

  /// Public Route convergence deadline. Three attempts by default.
  static Duration convergenceDeadline = const Duration(seconds: 2);

  /// Maximum Desired reasserts inside [convergenceDeadline].
  static int maxConvergenceAttempts = 3;

  /// Native teardown bound. `Duration.zero` waits only for [stopNative].
  static Duration teardownTimeout = const Duration(seconds: 2);

  final FlutterAiCommunicationsPlatform _platform;
  final void Function() _onStopped;
  final Logger _logger;
  final SoundFloor _floor;
  final BargeIn _bargeIn;
  final PlaybackTimeline _playback;
  final EndpointPreference _endpoints;
  final StreamController<Uint8List> _captureController;
  final StreamController<IsolationEvent> _isolationController;
  final StreamController<Coverage> _coverageController;
  final StreamController<SessionStatus> _statusController;

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
  var _stopping = false;
  var _isolationMissing = false;
  var _interrupted = false;
  var _stalled = false;
  var _graphGeneration = 1;
  Future<void> _queue = Future<void>.value();
  final Completer<void> _whenStopped = Completer<void>();
  final Set<_ParkReason> _parkReasons = <_ParkReason>{};
  Timer? _stallTimer;
  var _livenessGeneration = 0;
  Timer? _convergenceTimer;
  DateTime? _convergenceStartedAt;
  var _convergenceAttempts = 0;
  final Set<String> _unusablePairIds = <String>{};
  IsolationEvent _lastIsolation = const IsolationEvent(IsolationState.unknown);
  PairingSnapshot _desired;
  PairingSnapshot _applied;
  PairingSnapshot _observed;
  var _preferenceControlled = true;
  String? _explicitCaptureId;
  String? _explicitRenderId;
  var _generation = 1;
  String? _routeChangeCause = 'start';
  var _lifecycle = SessionLifecycle.starting;
  SessionStatus _status = const SessionStatus.starting();
  List<Endpoint> _catalog;
  Coverage _hostCoverage = const Coverage.ok();
  Coverage _pathCoverage = const Coverage.ok();
  var _captureFrameCount = 0;
  double? _recentRms;
  DateTime? _lastCaptureAt;
  AudioFormat? _nativeCaptureFormat;
  AudioFormat? _nativePlaybackFormat;
  var _captureConversionPath = ConversionPath.identity;
  var _playbackConversionPath = ConversionPath.identity;
  List<FormatCandidateFailure> _formatFailures = const [];
  final AudioTranscoder _captureTranscoder = AudioTranscoder();
  final AudioTranscoder _playbackTranscoder = AudioTranscoder();
  final AudioTranscoder _floorTranscoder = AudioTranscoder();

  /// Capture-out Format. Defaults to PCM16 LE mono 24 kHz.
  final AudioFormat captureFormat;

  /// Playback-in Format. May differ from [captureFormat].
  final AudioFormat playbackFormat;

  /// Preference the host passed to [CommunicationsManager.start]. Never rewritten.
  final SessionPreference preference;

  /// Whether barge-in is local or left to remote VAD.
  final BargeInPolicy bargeInPolicy;

  /// Capture, playback, duplex, or no audio edges.
  final SessionDirection direction;

  /// Whether this Session requested camera send.
  final bool cameraSend;

  /// Requested Video Format.
  final VideoFormat videoFormat;

  /// Camera preference used at start.
  final CameraPreference cameraPreference;

  /// v1 is [NoneVideoProcessor].
  final VideoProcessor videoProcessor;

  /// Host-provided Session purpose. Named by [StartAlreadyActive].
  final String? purpose;

  /// Floor-applied capture bytes. Mute emits silence on this same stream.
  late final Stream<Uint8List> capture;

  /// Isolation signals. Host owns every prompt string.
  late final Stream<IsolationEvent> isolation;

  /// Combined audio-path and host Coverage.
  late final Stream<Coverage> coverage;

  /// Structured readiness snapshots. Late subscribers receive the current
  /// snapshot.
  late final Stream<SessionStatus> statuses;

  /// Last Isolation event. Host UI can seed from this before listening.
  IsolationEvent get lastIsolation => _lastIsolation;

  /// Current structured status.
  SessionStatus get status => _status;

  /// Route and media observations. Never includes captured audio bytes.
  SessionDiagnostics get diagnostics {
    _playback.observe();
    return SessionDiagnostics(
      desired: _desired,
      applied: _applied,
      observed: _observed,
      preferenceControlled: _preferenceControlled,
      lifecycle: _lifecycle,
      catalog: List<Endpoint>.unmodifiable(_catalog),
      selectionGeneration: _generation,
      routeChangeCause: _routeChangeCause,
      captureFrameCount: _captureFrameCount,
      recentRms: _recentRms,
      lastCaptureAt: _lastCaptureAt,
      playbackAccepted: _playback.accepted,
      playbackQueued: _playback.queued,
      playbackRendered: _playback.rendered,
      playbackFlushed: _playback.flushed,
      requestedCaptureFormat: captureFormat,
      requestedPlaybackFormat: playbackFormat,
      nativeCaptureFormat: _nativeCaptureFormat,
      nativePlaybackFormat: _nativePlaybackFormat,
      edgeCaptureFormat: captureFormat,
      edgePlaybackFormat: playbackFormat,
      captureConversionPath: _captureConversionPath,
      playbackConversionPath: _playbackConversionPath,
      formatFailures: List<FormatCandidateFailure>.unmodifiable(
        _formatFailures,
      ),
      acousticProfile: _floor.profile,
      baselineStep: _floor.profile?.baselineStep,
      profileConfidence: _floor.profile?.confidence,
      captureProcessor: _floor.processor,
      activeFloor: _floor.threshold(
        routeClass: _selectedRouteClass(),
        isolationMissing: _isolationMissing,
      ),
    );
  }

  /// Whether the user's voice is replaced with silence frames.
  bool get isMuted => _muted;

  /// Whether capture and playback are parked.
  bool get isPaused => _paused;

  /// Whether [stop] has ended this Session.
  bool get isStopped => _stopped;

  /// Whether native teardown is in flight.
  bool get isStopping => _stopping && !_whenStopped.isCompleted;

  /// Completes when [stop] has released manager ownership.
  Future<void> get whenStopped => _whenStopped.future;

  /// Current sound floor. Ephemeral picks do not write [preference].
  double? get soundFloor => _floor.fixed;

  /// Capture processor applied to the one Capture stream.
  CaptureProcessor get captureProcessor => _floor.processor;

  /// Desired Pair. Ephemeral; does not write [preference].
  PairingSnapshot get pairing => _desired;

  /// Ephemeral capture Endpoint id, if the user overrode [preference].
  String? get selectedCaptureId => _desired.captureId;

  /// Ephemeral render Endpoint id, if the user overrode [preference].
  String? get selectedRenderId => _desired.renderId;

  /// Explicit or resolved camera id.
  String? get selectedCameraId => _cameraId;

  /// Whether outbound video is enabled (not Camera-off).
  bool get isCameraEnabled => _cameraEnabled;

  /// Whether Mute-video is substituting black frames.
  bool get isVideoMuted => _videoMuted;

  /// Local send Video surface, if video is running.
  VideoSurface? get videoSurface => _videoSurface;

  /// Negotiated Native Video Format, if video is running.
  VideoFormat? get nativeVideoFormat => _nativeVideoFormat;

  /// Why video is not running: `denied`, `restricted`, `none`, `no-mode`, or null.
  String? get videoUnavailableReason => _videoUnavailableReason;

  /// Whether remotes are still receiving a video send (including black frames).
  bool get isSendingVideo =>
      cameraSend &&
      _cameraEnabled &&
      _videoSurface != null &&
      !_stopped &&
      !_paused;

  /// Start-able snapshot of this Session. Does not include Transport or streams.
  SessionSettings get settings => SessionSettings(
    direction: direction,
    cameraSend: cameraSend,
    captureFormat: captureFormat,
    playbackFormat: playbackFormat,
    videoFormat: videoFormat,
    preference: SessionPreference(
      captureId: selectedCaptureId,
      renderId: selectedRenderId,
      soundFloor: preference.soundFloor,
      processor: preference.processor,
      noiseCancelling: preference.noiseCancelling,
      endpoints: _endpoints,
    ),
    cameraPreference: cameraPreference,
    cameraId: _cameraId,
    videoProcessor: videoProcessor,
    muted: _muted,
    cameraEnabled: _cameraEnabled,
    purpose: purpose,
    bargeInPolicy: bargeInPolicy,
  );

  String? _cameraId;
  late bool _cameraEnabled;
  late bool _videoMuted;
  VideoSurface? _videoSurface;
  VideoFormat? _nativeVideoFormat;
  String? _videoUnavailableReason;

  /// Renders [bytes] in [playbackFormat]. No-op while paused, stopped, or
  /// capture-only.
  Future<void> play(Uint8List bytes) async {
    if (_stopped || _paused || !direction.hasPlayback) {
      return;
    }
    _bargeIn.onPlay();
    _playback.schedule(bytes);
    _log(PipelineLog.playback, {
      'event': 'accepted',
      'accepted': _playback.accepted,
      'queued': _playback.queued,
    });
    await _platform.play(_toNativePlayback(bytes));
    _playback.observe();
    _log(PipelineLog.playback, {
      'event': 'queued',
      'rendered': _playback.rendered,
      'queued': _playback.queued,
    });
  }

  /// Live camera switch. Remotes see it. Does not write Camera preference.
  Future<void> selectCamera(String cameraId) async {
    if (_stopped) {
      return;
    }
    _cameraId = cameraId;
    await _platform.selectCameraNative(cameraId);
  }

  /// Mute-video: black frames, graph stays up.
  Future<void> muteVideo() async {
    if (_stopped || !_cameraEnabled) {
      return;
    }
    _videoMuted = true;
    await _platform.setMuteVideoNative(true);
  }

  /// Restores real frames on the same send path.
  Future<void> unmuteVideo() async {
    if (_stopped || !_cameraEnabled) {
      return;
    }
    _videoMuted = false;
    await _platform.setMuteVideoNative(false);
  }

  /// Camera-off when [enabled] is false. Audio continues.
  Future<void> setCameraEnabled(bool enabled) async {
    if (_stopped) {
      return;
    }
    _cameraEnabled = enabled;
    if (!enabled) {
      _videoMuted = false;
      _videoSurface = null;
    }
    await _platform.setCameraEnabledNative(enabled);
    if (enabled) {
      _videoSurface = _platform.lastVideoSurface;
    }
  }

  /// Attach camera send later on the same Session. Does not replace [capture].
  Future<void> enableVideo({
    String? cameraId,
    VideoFormat? videoFormat,
    VideoProcessor processor = const NoneVideoProcessor(),
  }) async {
    if (_stopped) {
      return;
    }
    final permission = await _platform.requestCameraPermission();
    if (permission != CameraPermission.granted) {
      _videoUnavailableReason = permission.name;
      _publishStatus(const SessionStatus.videoNotRunning());
      return;
    }
    final cameras = await _platform.enumerateCameras();
    final resolved = cameraPreference.resolve(cameras) ?? cameras.firstOrNull;
    final id = cameraId ?? _cameraId ?? resolved?.id;
    if (id == null) {
      _videoUnavailableReason = 'none';
      _publishStatus(const SessionStatus.videoNotRunning());
      return;
    }
    final start = await _platform.startCameraNative(
      cameraId: id,
      videoFormat: videoFormat ?? this.videoFormat,
      enabled: true,
      muted: false,
    );
    if (start != NativeGraphStart.started) {
      _videoUnavailableReason = 'none';
      _publishStatus(const SessionStatus.videoNotRunning());
      return;
    }
    _cameraId = id;
    _cameraEnabled = true;
    _videoMuted = false;
    _videoUnavailableReason = null;
    _videoSurface = _platform.lastVideoSurface;
    _nativeVideoFormat = _platform.lastNativeVideoFormat;
  }

  /// Mute keeps the same capture subscription and emits silence frames.
  void mute() {
    if (_stopped) {
      return;
    }
    _muted = true;
    _log(PipelineLog.mute, {'muted': true});
  }

  /// Restores voice frames on the same capture stream.
  void unmute() {
    if (_stopped) {
      return;
    }
    _muted = false;
    _log(PipelineLog.mute, {'muted': false});
  }

  /// Parks capture and playback. The Session and its streams stay put.
  Future<void> pause() => _pause(_ParkReason.user);

  /// Resumes on the same Session and the same broadcast streams.
  Future<void> resume() => _resume();

  /// Ephemeral Endpoint pick. Does not change [preference].
  Future<void> select({String? captureId, String? renderId}) {
    return _enqueue(() async {
      if (_stopped) {
        return;
      }
      if (captureId != null) {
        _explicitCaptureId = captureId;
      }
      if (renderId != null) {
        _explicitRenderId = renderId;
      }
      _preferenceControlled = false;
      await _applyResolution(
        _resolver.resolve(
          catalog: _catalog,
          preference: _endpoints,
          requireCapture: direction.hasCapture,
          requireRender: direction.hasPlayback,
          explicitCaptureId: _explicitCaptureId,
          explicitRenderId: _explicitRenderId,
          unusablePairIds: _unusablePairIds,
        ),
        cause: 'explicit',
      );
    });
  }

  /// Ephemeral sound floor. `null` returns to adaptive. Does not write [preference].
  void setSoundFloor(double? value) {
    if (_stopped) {
      return;
    }
    _floor.setFloor(value);
  }

  /// Ephemeral Capture processor. Does not write [preference].
  void setCaptureProcessor(CaptureProcessor processor) {
    if (_stopped) {
      return;
    }
    _floor.setProcessor(processor);
  }

  /// Opens the system Isolation UI. Host still owns copy.
  Future<void> openIsolationSettings() => _platform.openIsolationSettings();

  /// Ends the Session. Streams stay open until this object is discarded.
  Future<void> stop() {
    _stopping = true;
    _livenessGeneration++;
    _stallTimer?.cancel();
    _stallTimer = null;
    _convergenceTimer?.cancel();
    _convergenceTimer = null;
    return _enqueue(() async {
      if (_stopped) {
        return;
      }
      _stopped = true;
      _lifecycle = SessionLifecycle.stopped;
      try {
        await _platform.stopCameraNative();
        await _stopNativeBounded();
      } on Object catch (error, stack) {
        _logger.warning(
          PipelineLog.line(PipelineLog.stopped, {'result': 'teardownFailed'}),
          error,
          stack,
        );
      }
      // Do not await cancel/close. Some Dart streams complete those Futures
      // on a Timer, which never fires under FakeAsync unless time is pumped.
      unawaited(_captureSub?.cancel());
      unawaited(_isolationSub?.cancel());
      unawaited(_coverageSub?.cancel());
      unawaited(_catalogSub?.cancel());
      unawaited(_pathSub?.cancel());
      unawaited(_focusSub?.cancel());
      unawaited(_routeSub?.cancel());
      _captureSub = null;
      _isolationSub = null;
      _coverageSub = null;
      _catalogSub = null;
      _pathSub = null;
      _focusSub = null;
      _routeSub = null;
      unawaited(_captureController.close());
      unawaited(_isolationController.close());
      unawaited(_coverageController.close());
      _publishStatus(_computeStatus());
      unawaited(_statusController.close());
      _onStopped();
      _log(PipelineLog.stopped, {'generation': _generation});
      if (!_whenStopped.isCompleted) {
        _whenStopped.complete();
      }
    });
  }

  void _onNativeCapture(Uint8List bytes) {
    if (_stopped || _paused) {
      return;
    }
    final edge = _fromNativeCapture(bytes);
    final emitted = _muted ? Uint8List(edge.length) : _processCapture(edge);
    _noteCapture(emitted);
    _captureController.add(emitted);
  }

  Uint8List _fromNativeCapture(Uint8List bytes) {
    final native = _nativeCaptureFormat ?? captureFormat;
    if (native == captureFormat) {
      return bytes;
    }
    return _captureTranscoder.transcode(bytes, native, captureFormat);
  }

  Uint8List _toNativePlayback(Uint8List bytes) {
    final native = _nativePlaybackFormat ?? playbackFormat;
    if (native == playbackFormat) {
      return bytes;
    }
    return _playbackTranscoder.transcode(bytes, playbackFormat, native);
  }

  void _adoptAcousticProfile() {
    final endpoint = _byId(_desired.captureId);
    if (endpoint == null) {
      return;
    }
    const classifier = AcousticClassifier();
    final profile = classifier.classify(endpoint);
    _floor.setProfile(profile);
    _log(PipelineLog.profileClassified, {
      'family': profile.family.name,
      'baselineStep': profile.baselineStep,
      'confidence': profile.confidence.name,
      'provenance': profile.provenance.name,
      'matchId': profile.matchId,
    });
  }

  void _adoptNativeFormats(NativeFormatReport report) {
    final adopted = report.withEdges(
      capture: captureFormat,
      playback: playbackFormat,
    );
    _captureTranscoder.reset();
    _playbackTranscoder.reset();
    _floorTranscoder.reset();
    _nativeCaptureFormat = adopted.capture;
    _nativePlaybackFormat = adopted.playback;
    _captureConversionPath = adopted.capturePath;
    _playbackConversionPath = adopted.playbackPath;
    _formatFailures = adopted.failures;
    _log(PipelineLog.formatNegotiated, {
      'capture': _nativeCaptureFormat?.toString(),
      'playback': _nativePlaybackFormat?.toString(),
      'capturePath': _captureConversionPath.name,
      'playbackPath': _playbackConversionPath.name,
    });
  }

  Uint8List _processCapture(Uint8List bytes) {
    final working = captureFormat.encoding == AudioEncoding.pcm16le
        ? bytes
        : _floorTranscoder.toWorking(bytes, captureFormat);
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
    return captureFormat.encoding == AudioEncoding.pcm16le
        ? gated
        : _floorTranscoder.fromWorking(gated, captureFormat);
  }

  void _noteCapture(Uint8List bytes) {
    _captureFrameCount++;
    _recentRms = _rms(bytes);
    _lastCaptureAt = DateTime.now();
    if (_lifecycle == SessionLifecycle.starting || _stalled) {
      _lifecycle = SessionLifecycle.live;
    }
    _stalled = false;
    _livenessGeneration++;
    _armStallWatch();
    _log(PipelineLog.capture, {
      'frames': _captureFrameCount,
      'rms': _recentRms?.toStringAsFixed(4),
      'muted': _muted,
    });
    _publishStatus(_computeStatus());
  }

  Future<void> _flushBargeIn(int sampleRate) async {
    await _platform.flushPlayback();
    _playback.flush();
    _log(PipelineLog.playback, {
      'event': 'flushed',
      'flushed': _playback.flushed,
    });
    _bargeIn.onIdle();
    for (final frame in _bargeIn.takePreroll()) {
      final gated = _floor.apply(
        frame,
        sampleRate: sampleRate,
        routeClass: _selectedRouteClass(),
        isolationMissing: _isolationMissing,
      );
      if (gated.any((b) => b != 0)) {
        _noteCapture(gated);
        _captureController.add(
          captureFormat.encoding == AudioEncoding.pcm16le
              ? gated
              : _floorTranscoder.fromWorking(gated, captureFormat),
        );
      }
    }
  }

  void _onIsolation(IsolationEvent event) {
    final presented = switch (event.state) {
      IsolationState.off when preference.noiseCancelling =>
        const IsolationEvent(IsolationState.required),
      IsolationState.required when !preference.noiseCancelling =>
        const IsolationEvent(IsolationState.off),
      _ => event,
    };
    _lastIsolation = presented;
    // Prompt via Isolation required. If Isolation stays off, unavailable, or
    // the user refuses, adapt: raise the Sound floor as if there is no
    // Isolation / noise cancelling.
    _isolationMissing = switch (presented.state) {
      IsolationState.off ||
      IsolationState.required ||
      IsolationState.unavailable => true,
      _ => false,
    };
    _isolationController.add(presented);
    _log(PipelineLog.isolation, {
      'state': presented.state.name,
      'missing': _isolationMissing,
    });
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
      unawaited(_pause(_ParkReason.coverage));
    } else if (next.level == CoverageLevel.ok && !_stopped) {
      unawaited(_clearPark(_ParkReason.coverage));
    }
  }

  void _onAudioFocus(AudioFocusState state) {
    if (state == AudioFocusState.interrupted) {
      unawaited(_pause(_ParkReason.interruption));
    } else {
      unawaited(_clearPark(_ParkReason.interruption));
    }
  }

  void _onCatalog(List<Endpoint> catalog) {
    _catalog = List<Endpoint>.of(catalog);
    if (!_preferenceControlled) {
      final captureGone =
          _explicitCaptureId != null && _byId(_explicitCaptureId) == null;
      final renderGone =
          _explicitRenderId != null && _byId(_explicitRenderId) == null;
      if (captureGone) {
        _explicitCaptureId = null;
      }
      if (renderGone) {
        _explicitRenderId = null;
      }
      if (_explicitCaptureId == null && _explicitRenderId == null) {
        _preferenceControlled = true;
      }
    }
    unawaited(
      _enqueue(() {
        return _applyResolution(
          _resolver.resolve(
            catalog: _catalog,
            preference: _endpoints,
            requireCapture: direction.hasCapture,
            requireRender: direction.hasPlayback,
            explicitCaptureId: _explicitCaptureId,
            explicitRenderId: _explicitRenderId,
            unusablePairIds: _unusablePairIds,
          ),
          cause: _preferenceControlled ? 'preference' : 'catalog',
        );
      }),
    );
  }

  void _onOsRoute(OsRouteChange change) {
    if (change.generation != null && change.generation! < _graphGeneration) {
      return;
    }
    _observed = PairingSnapshot(
      captureId: change.captureId ?? _observed.captureId,
      renderId: change.renderId ?? _observed.renderId,
    );
    _log(PipelineLog.observed, _routeFields(_observed, cause: 'os'));
    if (diagnostics.observedMatchesDesired) {
      _resetConvergence();
      _publishStatus(_computeStatus());
      return;
    }
    _publishStatus(_computeStatus());
    if (_hasObservedRoute) {
      _scheduleConvergence();
    }
  }

  Future<void> _applyResolution(
    PreferenceResolution resolution, {
    required String cause,
  }) async {
    if (_stopped || _stopping) {
      return;
    }
    _preferenceControlled = resolution.preferenceControlled;
    if (resolution.exhausted) {
      _desired = const PairingSnapshot();
      _routeChangeCause = cause;
      _generation++;
      _log(PipelineLog.desired, _routeFields(_desired, cause: cause));
      _publishStatus(_computeStatus());
      return;
    }
    final changed = resolution.desired != _desired;
    _desired = resolution.desired;
    if (changed) {
      _generation++;
      _routeChangeCause = cause;
      _log(PipelineLog.desired, _routeFields(_desired, cause: cause));
      _adoptAcousticProfile();
    }
    if (_applied != _desired) {
      _applied = _desired;
      _resetConvergence();
      _log(PipelineLog.applied, _routeFields(_applied, cause: cause));
      await _platform.selectEndpoints(
        captureId: _applied.captureId,
        renderId: _applied.renderId,
      );
      _adoptNativeFormats(_platform.lastNativeFormats);
    }
    _publishStatus(_computeStatus());
    if (!diagnostics.observedMatchesDesired && _hasObservedRoute) {
      _scheduleConvergence();
    }
  }

  SessionStatus _computeStatus() {
    if (_stopped) {
      return SessionStatus(
        severity: StatusSeverity.success,
        code: SessionStatusCode.stopped,
        recoverability: StatusRecoverability.none,
        usability: StatusUsability.unusable,
        action: SessionAction.none,
        purpose: purpose,
        generation: _generation,
      );
    }
    if (_paused) {
      return SessionStatus(
        severity: StatusSeverity.warning,
        code: _interrupted
            ? SessionStatusCode.interrupted
            : SessionStatusCode.paused,
        recoverability: StatusRecoverability.hostAction,
        usability: StatusUsability.degraded,
        action: SessionAction.wait,
        purpose: purpose,
        generation: _generation,
      );
    }
    if (_desired.captureId == null && _desired.renderId == null) {
      return SessionStatus.noUsablePair(
        purpose: purpose,
        generation: _generation,
      );
    }
    if (!diagnostics.observedMatchesDesired) {
      final pending = _observed.captureId == null && _observed.renderId == null;
      final exhausted =
          _convergenceAttempts >= maxConvergenceAttempts ||
          (_convergenceStartedAt != null &&
              DateTime.now().difference(_convergenceStartedAt!) >=
                  convergenceDeadline);
      return SessionStatus(
        severity: StatusSeverity.warning,
        code: pending
            ? SessionStatusCode.routeConverging
            : SessionStatusCode.routeMismatch,
        recoverability: pending || !exhausted
            ? StatusRecoverability.automatic
            : StatusRecoverability.hostAction,
        usability: StatusUsability.degraded,
        action: pending || !exhausted
            ? SessionAction.wait
            : SessionAction.selectPair,
        purpose: purpose,
        generation: _generation,
        attempt: _convergenceAttempts,
        maxAttempts: maxConvergenceAttempts,
      );
    }
    if (_stalled) {
      return SessionStatus(
        severity: StatusSeverity.warning,
        code: SessionStatusCode.captureStalled,
        recoverability: StatusRecoverability.automatic,
        usability: StatusUsability.degraded,
        action: SessionAction.wait,
        purpose: purpose,
        generation: _generation,
      );
    }
    if (direction.hasCapture && _captureFrameCount == 0) {
      return SessionStatus.starting(purpose: purpose, generation: _generation);
    }
    return SessionStatus.ready(purpose: purpose, generation: _generation);
  }

  void _publishStatus(SessionStatus next) {
    if (_status == next) {
      return;
    }
    _status = next;
    _log(PipelineLog.status, {
      'statusCode': next.code.name,
      'severity': next.severity.name,
      'action': next.action.name,
      'generation': next.generation,
      'purpose': next.purpose,
    });
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  Map<String, Object?> _routeFields(
    PairingSnapshot pair, {
    required String cause,
  }) => {
    'captureId': pair.captureId,
    'renderId': pair.renderId,
    'cause': cause,
    'generation': _generation,
    'preferenceControlled': _preferenceControlled,
  };

  void _log(String code, [Map<String, Object?> fields = const {}]) {
    _logger.info(PipelineLog.line(code, fields));
  }

  Endpoint? _byId(String? id) {
    if (id == null) {
      return null;
    }
    return _catalog.where((endpoint) => endpoint.id == id).firstOrNull;
  }

  RouteClass? _selectedRouteClass() {
    return _byId(_desired.captureId)?.routeClass;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final previous = _queue;
    final gate = Completer<void>();
    _queue = gate.future;
    return previous.catchError((_) {}).then((_) => action()).whenComplete(() {
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
  }

  Future<void> _pause(_ParkReason reason) {
    return _enqueue(() async {
      if (_stopped) {
        return;
      }
      _parkReasons.add(reason);
      if (reason == _ParkReason.interruption) {
        _interrupted = true;
      }
      if (_paused) {
        _publishStatus(_computeStatus());
        return;
      }
      _paused = true;
      _lifecycle = SessionLifecycle.paused;
      _bargeIn.onIdle();
      _playback.pause();
      _stallTimer?.cancel();
      await _platform.pauseNative();
      _log(PipelineLog.paused, {'reason': reason.name});
      _publishStatus(_computeStatus());
    });
  }

  Future<void> _clearPark(_ParkReason reason) {
    return _enqueue(() async {
      if (_stopped) {
        return;
      }
      _parkReasons.remove(reason);
      if (reason == _ParkReason.interruption) {
        _interrupted = false;
      }
      if (_parkReasons.isEmpty && _paused) {
        await _doResume();
      } else {
        _publishStatus(_computeStatus());
      }
    });
  }

  Future<void> _resume() {
    return _enqueue(() async {
      if (_stopped || !_paused) {
        return;
      }
      _parkReasons.remove(_ParkReason.user);
      _parkReasons.remove(_ParkReason.interruption);
      _interrupted = false;
      if (_parkReasons.isNotEmpty) {
        _publishStatus(_computeStatus());
        return;
      }
      await _doResume();
    });
  }

  Future<void> _doResume() async {
    await _platform.resumeNative();
    _paused = false;
    _interrupted = false;
    _lifecycle = SessionLifecycle.live;
    _playback.resume();
    _log(PipelineLog.resumed);
    _armStallWatch();
    if (!diagnostics.observedMatchesDesired) {
      await _convergeObserved();
    }
    _publishStatus(_computeStatus());
  }

  void _armStallWatch() {
    _stallTimer?.cancel();
    if (_stopped || _stopping || _paused || !direction.hasCapture) {
      return;
    }
    final generation = ++_livenessGeneration;
    _stallTimer = Timer(stallTimeout, () {
      if (generation != _livenessGeneration) {
        return;
      }
      unawaited(_onCaptureStall(generation));
    });
  }

  Future<void> _onCaptureStall(int generation) {
    return _enqueue(() async {
      if (generation != _livenessGeneration ||
          _stopped ||
          _paused ||
          !direction.hasCapture) {
        return;
      }
      _stalled = true;
      _lifecycle = SessionLifecycle.starting;
      _log(PipelineLog.capture, {
        'event': 'stalled',
        'frames': _captureFrameCount,
      });
      _publishStatus(_computeStatus());
      await _resetGraph();
      _armStallWatch();
    });
  }

  bool get _hasObservedRoute =>
      _observed.captureId != null || _observed.renderId != null;

  void _resetConvergence() {
    _convergenceTimer?.cancel();
    _convergenceTimer = null;
    _convergenceStartedAt = null;
    _convergenceAttempts = 0;
  }

  void _scheduleConvergence() {
    if (_stopped || _stopping || diagnostics.observedMatchesDesired) {
      return;
    }
    _convergenceStartedAt ??= DateTime.now();
    _convergenceTimer?.cancel();
    final elapsed = DateTime.now().difference(_convergenceStartedAt!);
    final remaining = convergenceDeadline - elapsed;
    if (remaining <= Duration.zero ||
        _convergenceAttempts >= maxConvergenceAttempts) {
      unawaited(_enqueue(_failConvergence));
      return;
    }
    final delay = Duration(
      milliseconds:
          (remaining.inMilliseconds /
                  (maxConvergenceAttempts - _convergenceAttempts))
              .ceil()
              .clamp(1, remaining.inMilliseconds),
    );
    _convergenceTimer = Timer(delay, () {
      unawaited(_enqueue(_convergeObserved));
    });
  }

  Future<void> _convergeObserved() async {
    if (_stopped || _stopping || diagnostics.observedMatchesDesired) {
      _resetConvergence();
      return;
    }
    _convergenceStartedAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(_convergenceStartedAt!);
    if (_convergenceAttempts >= maxConvergenceAttempts ||
        elapsed >= convergenceDeadline) {
      await _failConvergence();
      return;
    }
    _convergenceAttempts++;
    _applied = _desired;
    _log(PipelineLog.applied, {
      ..._routeFields(_applied, cause: 'converge'),
      'attempt': _convergenceAttempts,
      'maxAttempts': maxConvergenceAttempts,
    });
    await _platform.selectEndpoints(
      captureId: _applied.captureId,
      renderId: _applied.renderId,
    );
    _adoptNativeFormats(_platform.lastNativeFormats);
    _publishStatus(_computeStatus());
    if (!diagnostics.observedMatchesDesired) {
      _scheduleConvergence();
    } else {
      _resetConvergence();
    }
  }

  Future<void> _failConvergence() async {
    _convergenceTimer?.cancel();
    _convergenceTimer = null;
    final pairId = _pairIdFor(_desired);
    if (_preferenceControlled && pairId != null) {
      _unusablePairIds.add(pairId);
      _log(PipelineLog.desired, {
        ..._routeFields(_desired, cause: 'unusable'),
        'pairId': pairId,
      });
      await _applyResolution(
        _resolver.resolve(
          catalog: _catalog,
          preference: _endpoints,
          requireCapture: direction.hasCapture,
          requireRender: direction.hasPlayback,
          explicitCaptureId: _explicitCaptureId,
          explicitRenderId: _explicitRenderId,
          unusablePairIds: _unusablePairIds,
        ),
        cause: 'preference',
      );
      return;
    }
    _publishStatus(_computeStatus());
  }

  String? _pairIdFor(PairingSnapshot pair) {
    return _byId(pair.captureId)?.pairId ?? _byId(pair.renderId)?.pairId;
  }

  Future<void> _stopNativeBounded() {
    if (teardownTimeout <= Duration.zero) {
      return _platform.stopNative();
    }
    final done = Completer<void>();
    final timer = Timer(teardownTimeout, () {
      if (!done.isCompleted) {
        done.completeError(TimeoutException('stopNative'));
      }
    });
    _platform
        .stopNative()
        .then((_) {
          if (!done.isCompleted) {
            done.complete();
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (!done.isCompleted) {
            done.completeError(error, stack);
          }
        });
    return done.future.whenComplete(timer.cancel);
  }

  Future<void> _resetGraph() async {
    _graphGeneration++;
    _log(PipelineLog.nativeReset, {
      'generation': _graphGeneration,
      'captureId': _applied.captureId,
      'renderId': _applied.renderId,
    });
    try {
      final result = await _platform.resetNative(
        captureId: _applied.captureId,
        renderId: _applied.renderId,
        captureFormat: captureFormat,
        playbackFormat: playbackFormat,
        noiseCancelling: preference.noiseCancelling,
      );
      if (result == NativeGraphStart.started) {
        _adoptNativeFormats(_platform.lastNativeFormats);
      }
    } on Object catch (error, stack) {
      _logger.warning(
        PipelineLog.line(PipelineLog.nativeReset, {'result': 'failed'}),
        error,
        stack,
      );
    }
  }

  double _rms(Uint8List bytes) {
    if (bytes.length < 2) {
      return 0;
    }
    final data = ByteData.sublistView(bytes);
    var sum = 0.0;
    final n = bytes.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += s * s;
    }
    return math.sqrt(sum / n);
  }
}

enum _ParkReason { user, coverage, interruption }
