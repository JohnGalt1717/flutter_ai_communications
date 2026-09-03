part of '../flutter_ai_communications.dart';

/// Public module that creates and drives at most one live [Session].
final class CommunicationsManager {
  /// Creates a Communications manager.
  ///
  /// [platform] defaults to the registered federated adapter. Tests inject
  /// [FakeCommunicationsPlatform].
  CommunicationsManager({
    FlutterAiCommunicationsPlatform? platform,
    CoverageSource? coverageSource,
    Logger? logger,
  }) : _platform = platform ?? FlutterAiCommunicationsPlatform.instance,
       _coverageSource = coverageSource ?? DefaultCoverageSource(),
       _logger = logger ?? Logger(PipelineLog.loggerName);

  final FlutterAiCommunicationsPlatform _platform;
  final CoverageSource _coverageSource;
  final Logger _logger;
  static const _resolver = PreferenceResolver();

  Session? _session;
  CameraPreview? _preview;
  EndpointPreference _boundPreference = const EndpointPreference();
  CameraPreference _boundCameraPreference = const CameraPreference();

  /// The live Session, if [start] succeeded and [Session.stop] has not run.
  Session? get session => _session;

  /// In-call Camera preview, if running.
  CameraPreview? get cameraPreview => _preview;

  /// Idle camera catalog.
  Future<List<CameraEndpoint>> cameras() => _platform.enumerateCameras();

  /// Idle or live Screen source catalog snapshot.
  Future<List<ScreenSource>> screenSources() =>
      _platform.enumerateScreenSources();

  /// Host-persisted Camera preference. Does not end a live Session.
  CameraPreference get boundCameraPreference => _boundCameraPreference;

  /// Replaces the bound Camera preference. Does not stop a Session.
  void bindCameraPreference(CameraPreference preference) {
    _boundCameraPreference = preference;
  }

  /// Idle or live Endpoint catalog from the platform adapter.
  Future<List<Endpoint>> endpoints() => _platform.enumerateEndpoints();

  /// Live catalog updates.
  Stream<List<Endpoint>> get endpointCatalog => _platform.endpointCatalog;

  /// Host-persisted Endpoint preference used when start omits
  /// [SessionPreference.endpoints].
  EndpointPreference get boundPreference => _boundPreference;

  /// Replaces the bound Endpoint preference. Ends a live Session.
  Future<void> bindPreference(EndpointPreference preference) async {
    _boundPreference = preference;
    _log(PipelineLog.preferenceBound, {
      'count': preference.entries.length,
      'empty': preference.isEmpty,
    });
    await _session?.stop();
  }

  /// Requests permission, then starts at most one Session.
  ///
  /// Expected failures are [StartResult] values, not thrown exceptions.
  Future<StartResult> start({
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    SessionPreference preference = const SessionPreference(),
    BargeInPolicy bargeInPolicy = BargeInPolicy.local,
    SessionDirection direction = SessionDirection.duplex,
    String? purpose,
    SessionSettings? settings,
    bool cameraSend = false,
    VideoFormat? videoFormat,
    CameraPreference cameraPreference = const CameraPreference(),
    String? cameraId,
    VideoProcessor videoProcessor = const NoneVideoProcessor(),
    bool cameraEnabled = true,
    bool muted = false,
  }) async {
    final requestedPurpose = purpose;
    if (settings != null) {
      captureFormat ??= settings.captureFormat;
      playbackFormat ??= settings.playbackFormat;
      preference = settings.preference;
      bargeInPolicy = settings.bargeInPolicy;
      direction = settings.direction;
      purpose = settings.purpose ?? purpose;
      cameraSend = settings.cameraSend;
      videoFormat = settings.videoFormat ?? videoFormat;
      cameraPreference = settings.cameraPreference;
      cameraId = settings.cameraId ?? cameraId;
      videoProcessor = settings.videoProcessor;
      cameraEnabled = settings.cameraEnabled;
      muted = settings.muted;
    }
    purpose = requestedPurpose ?? purpose;
    _log(PipelineLog.startRequested, {
      'direction': direction.name,
      'purpose': purpose,
      'cameraSend': cameraSend,
    });
    final live = _session;
    if (live != null && !live.isStopping) {
      _log(PipelineLog.startAlreadyActive, {'purpose': live.purpose});
      return StartAlreadyActive(purpose: live.purpose);
    }
    if (live != null && live.isStopping) {
      await live.whenStopped;
    }
    if (_session != null) {
      _log(PipelineLog.startAlreadyActive, {'purpose': _session!.purpose});
      return StartAlreadyActive(purpose: _session!.purpose);
    }

    final capture = captureFormat ?? AudioTranscoder.defaultEdge;
    final playback = playbackFormat ?? AudioTranscoder.defaultEdge;
    if (!capture.isSupported || !playback.isSupported) {
      return StartFailed(ArgumentError('unsupported Format'));
    }
    if (capture.encoding == AudioEncoding.opus ||
        playback.encoding == AudioEncoding.opus) {
      return StartFailed(UnsupportedError('opus'));
    }

    if (direction.hasCapture) {
      final MicrophonePermission permission;
      try {
        permission = await _platform.requestMicrophonePermission();
      } catch (error, stack) {
        _logger.warning(
          PipelineLog.line(PipelineLog.permission, {'result': 'failed'}),
          error,
          stack,
        );
        return StartFailed(error);
      }
      _log(PipelineLog.permission, {
        'requested': true,
        'result': permission.name,
      });
      switch (permission) {
        case MicrophonePermission.denied:
          return const StartDenied();
        case MicrophonePermission.restricted:
          return const StartRestricted();
        case MicrophonePermission.granted:
          break;
      }
    } else {
      _log(PipelineLog.permission, {'requested': false, 'result': 'skipped'});
    }

    final catalog = await _platform.enumerateEndpoints();
    _log(PipelineLog.catalog, {'count': catalog.length});
    final resolvedPreference = preference.endpoints.isEmpty
        ? _boundPreference
        : preference.endpoints;
    final resolution = _resolver.resolve(
      catalog: catalog,
      preference: resolvedPreference,
      requireCapture: direction.hasCapture,
      requireRender: direction.hasPlayback,
      explicitCaptureId: preference.captureId,
      explicitRenderId: preference.renderId,
    );
    _log(PipelineLog.preferenceResolved, {
      'preferenceControlled': resolution.preferenceControlled,
      'captureId': resolution.desired.captureId,
      'renderId': resolution.desired.renderId,
      'exhausted': resolution.exhausted,
    });
    if (resolution.exhausted &&
        (direction.hasCapture || direction.hasPlayback)) {
      return const StartUnavailable();
    }

    if (direction.hasCapture || direction.hasPlayback) {
      final NativeGraphStart native;
      try {
        native = await _platform.startNative(
          captureId: resolution.desired.captureId,
          renderId: resolution.desired.renderId,
          captureFormat: capture,
          playbackFormat: playback,
          noiseCancelling: preference.noiseCancelling,
        );
      } catch (error, stack) {
        _logger.warning(
          PipelineLog.line(PipelineLog.nativeStart, {'result': 'failed'}),
          error,
          stack,
        );
        return StartFailed(error);
      }
      _log(PipelineLog.nativeStart, {'result': native.name});
      if (native != NativeGraphStart.started) {
        return switch (native) {
          NativeGraphStart.unavailable => const StartUnavailable(),
          NativeGraphStart.failed => const StartFailed(),
          NativeGraphStart.started => const StartFailed(),
        };
      }
    }

    var resolvedCameraId = cameraId;
    var cameraEnabledOut = cameraEnabled;
    var videoSurface = _platform.lastVideoSurface;
    var nativeVideo = _platform.lastNativeVideoFormat;
    String? videoReason;
    if (cameraSend) {
      final cameraResult = await _startCamera(
        cameraId: cameraId,
        videoFormat: videoFormat ?? VideoFormat.defaultFormat,
        preference: cameraPreference.isEmpty
            ? _boundCameraPreference
            : cameraPreference,
        enabled: cameraEnabled,
      );
      resolvedCameraId = cameraResult.cameraId;
      cameraEnabledOut = cameraResult.enabled;
      videoSurface = cameraResult.surface;
      nativeVideo = cameraResult.nativeFormat;
      videoReason = cameraResult.reason;
    }

    final ready = _attachSession(
      captureFormat: capture,
      playbackFormat: playback,
      preference: preference,
      bargeInPolicy: bargeInPolicy,
      direction: direction,
      purpose: purpose,
      resolution: resolution,
      resolvedPreference: resolvedPreference,
      catalog: catalog,
      cameraSend: cameraSend,
      videoFormat: videoFormat ?? VideoFormat.defaultFormat,
      cameraPreference: cameraPreference.isEmpty
          ? _boundCameraPreference
          : cameraPreference,
      videoProcessor: videoProcessor,
      cameraId: resolvedCameraId,
      cameraEnabled: cameraEnabledOut,
      videoMuted: false,
      videoSurface: videoSurface,
      nativeVideoFormat: nativeVideo,
      videoUnavailableReason: videoReason,
    );
    if (muted) {
      ready.session.mute();
    }
    return ready;
  }

  Future<({
    String? cameraId,
    bool enabled,
    VideoSurface? surface,
    VideoFormat? nativeFormat,
    String? reason,
  })>
  _startCamera({
    required String? cameraId,
    required VideoFormat videoFormat,
    required CameraPreference preference,
    required bool enabled,
  }) async {
    try {
      final permission = await _platform.requestCameraPermission();
      if (permission != CameraPermission.granted) {
        return (
          cameraId: cameraId,
          enabled: false,
          surface: null,
          nativeFormat: null,
          reason: permission.name,
        );
      }
    } on Object {
      return (
        cameraId: cameraId,
        enabled: false,
        surface: null,
        nativeFormat: null,
        reason: 'denied',
      );
    }
    final cameras = await _platform.enumerateCameras();
    final resolved = cameraId != null
        ? cameras.where((camera) => camera.id == cameraId).firstOrNull
        : preference.resolve(cameras);
    if (resolved == null) {
      return (
        cameraId: cameraId,
        enabled: false,
        surface: null,
        nativeFormat: null,
        reason: 'none',
      );
    }
    final start = await _platform.startCameraNative(
      cameraId: resolved.id,
      videoFormat: videoFormat,
      enabled: enabled,
      muted: false,
    );
    if (start != NativeGraphStart.started) {
      return (
        cameraId: resolved.id,
        enabled: false,
        surface: null,
        nativeFormat: null,
        reason: 'none',
      );
    }
    if (_platform.lastNativeVideoFormat == null) {
      return (
        cameraId: resolved.id,
        enabled: false,
        surface: null,
        nativeFormat: null,
        reason: 'no-mode',
      );
    }
    return (
      cameraId: resolved.id,
      enabled: enabled,
      surface: _platform.lastVideoSurface,
      nativeFormat: _platform.lastNativeVideoFormat,
      reason: enabled ? null : null,
    );
  }

  StartReady _attachSession({
    required AudioFormat captureFormat,
    required AudioFormat playbackFormat,
    required SessionPreference preference,
    required BargeInPolicy bargeInPolicy,
    required SessionDirection direction,
    required String? purpose,
    required PreferenceResolution resolution,
    required EndpointPreference resolvedPreference,
    required List<Endpoint> catalog,
    bool cameraSend = false,
    VideoFormat videoFormat = VideoFormat.defaultFormat,
    CameraPreference cameraPreference = const CameraPreference(),
    VideoProcessor videoProcessor = const NoneVideoProcessor(),
    String? cameraId,
    bool cameraEnabled = true,
    bool videoMuted = false,
    VideoSurface? videoSurface,
    VideoFormat? nativeVideoFormat,
    String? videoUnavailableReason,
  }) {
    final session = Session._(
      platform: _platform,
      captureFormat: captureFormat,
      playbackFormat: playbackFormat,
      preference: preference,
      bargeInPolicy: bargeInPolicy,
      direction: direction,
      purpose: purpose,
      coverageSource: _coverageSource,
      desired: resolution.desired,
      preferenceControlled: resolution.preferenceControlled,
      endpoints: resolvedPreference,
      catalog: catalog,
      onStopped: () => _session = null,
      logger: _logger,
      nativeFormats: _platform.lastNativeFormats,
      cameraSend: cameraSend,
      videoFormat: videoFormat,
      cameraPreference: cameraPreference,
      videoProcessor: videoProcessor,
      cameraId: cameraId,
      cameraEnabled: cameraEnabled,
      videoMuted: videoMuted,
      videoSurface: videoSurface,
      nativeVideoFormat: nativeVideoFormat,
      videoUnavailableReason: videoUnavailableReason,
    );
    _session = session;
    _log(PipelineLog.sessionAttached, {
      'direction': direction.name,
      'purpose': purpose,
      'generation': session.diagnostics.selectionGeneration,
    });
    return StartReady(session);
  }

  /// In-call Camera preview. Fails if the Session is still sending video.
  Future<PreviewStartResult> startCameraPreview({
    String? cameraId,
    VideoFormat? videoFormat,
  }) async {
    final live = _session;
    if (live != null && live.isSendingVideo) {
      return const PreviewBlocked();
    }
    if (_preview != null) {
      await _preview!.stop();
    }
    final cameras = await _platform.enumerateCameras();
    final resolved =
        cameraId ??
        live?.selectedCameraId ??
        _boundCameraPreference.resolve(cameras)?.id ??
        cameras.firstOrNull?.id;
    if (resolved == null) {
      return const PreviewFailed('none');
    }
    final permission = await _platform.requestCameraPermission();
    if (permission != CameraPermission.granted) {
      return PreviewFailed(permission.name);
    }
    final start = await _platform.startCameraNative(
      cameraId: resolved,
      videoFormat: videoFormat ?? VideoFormat.defaultFormat,
      enabled: true,
      muted: false,
    );
    final surface = _platform.lastVideoSurface;
    if (start != NativeGraphStart.started || surface == null) {
      return const PreviewFailed('none');
    }
    final preview = CameraPreview._(
      platform: _platform,
      surface: surface,
      cameraId: resolved,
      onStopped: () => _preview = null,
    );
    _preview = preview;
    return PreviewReady(preview);
  }

  void _log(String code, [Map<String, Object?> fields = const {}]) {
    _logger.info(PipelineLog.line(code, fields));
  }
}
