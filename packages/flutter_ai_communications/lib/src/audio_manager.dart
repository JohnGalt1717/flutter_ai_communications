part of '../flutter_ai_communications.dart';

/// Public module that creates and drives at most one live [Session].
final class AudioManager {
  /// Creates an Audio manager.
  ///
  /// [platform] defaults to the registered federated adapter. Tests inject
  /// [FakeCommunicationsPlatform].
  AudioManager({
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
  EndpointPreference _boundPreference = const EndpointPreference();

  /// The live Session, if [start] succeeded and [Session.stop] has not run.
  Session? get session => _session;

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
  }) async {
    _log(PipelineLog.startRequested, {
      'direction': direction.name,
      'purpose': purpose,
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
    if (resolution.exhausted) {
      return const StartUnavailable();
    }

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

    return switch (native) {
      NativeGraphStart.unavailable => const StartUnavailable(),
      NativeGraphStart.failed => const StartFailed(),
      NativeGraphStart.started => _attachSession(
        captureFormat: capture,
        playbackFormat: playback,
        preference: preference,
        bargeInPolicy: bargeInPolicy,
        direction: direction,
        purpose: purpose,
        resolution: resolution,
        resolvedPreference: resolvedPreference,
        catalog: catalog,
      ),
    };
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
    );
    _session = session;
    _log(PipelineLog.sessionAttached, {
      'direction': direction.name,
      'purpose': purpose,
      'generation': session.diagnostics.selectionGeneration,
    });
    return StartReady(session);
  }

  void _log(String code, [Map<String, Object?> fields = const {}]) {
    _logger.info(PipelineLog.line(code, fields));
  }
}
