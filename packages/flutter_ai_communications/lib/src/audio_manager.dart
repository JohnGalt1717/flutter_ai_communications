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
       _logger = logger ?? Logger('AudioManager');

  final FlutterAiCommunicationsPlatform _platform;
  final CoverageSource _coverageSource;
  final Logger _logger;

  Session? _session;

  /// The live Session, if [start] succeeded and [Session.stop] has not run.
  Session? get session => _session;

  /// Idle or live Endpoint catalog from the platform adapter.
  Future<List<Endpoint>> endpoints() => _platform.enumerateEndpoints();

  /// Live catalog updates.
  Stream<List<Endpoint>> get endpointCatalog => _platform.endpointCatalog;

  /// Requests permission, then starts at most one Session.
  ///
  /// Expected failures are [StartResult] values, not thrown exceptions.
  Future<StartResult> start({
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    SessionPreference preference = const SessionPreference(),
    BargeInPolicy bargeInPolicy = BargeInPolicy.local,
  }) async {
    if (_session != null) {
      return const StartAlreadyActive();
    }

    final capture = captureFormat ?? AudioTranscoder.defaultEdge;
    final playback = playbackFormat ?? AudioTranscoder.defaultEdge;
    if (!capture.isSupported || !playback.isSupported) {
      return StartFailed(ArgumentError('unsupported Format'));
    }

    final MicrophonePermission permission;
    try {
      permission = await _platform.requestMicrophonePermission();
    } catch (error, stack) {
      _logger.warning('microphone permission request failed', error, stack);
      return StartFailed(error);
    }

    switch (permission) {
      case MicrophonePermission.denied:
        return const StartDenied();
      case MicrophonePermission.restricted:
        return const StartRestricted();
      case MicrophonePermission.granted:
        break;
    }

    final catalog = await _platform.enumerateEndpoints();
    final pairing = _initialPairing(catalog, preference);

    final NativeGraphStart native;
    try {
      native = await _platform.startNative(
        captureId: pairing.captureId,
        renderId: pairing.renderId,
      );
    } catch (error, stack) {
      _logger.warning('native start failed', error, stack);
      return StartFailed(error);
    }

    return switch (native) {
      NativeGraphStart.unavailable => const StartUnavailable(),
      NativeGraphStart.failed => const StartFailed(),
      NativeGraphStart.started => _attachSession(
        captureFormat: capture,
        playbackFormat: playback,
        preference: preference,
        bargeInPolicy: bargeInPolicy,
        pairing: pairing,
        catalog: catalog,
      ),
    };
  }

  PairingSnapshot _initialPairing(
    List<Endpoint> catalog,
    SessionPreference preference,
  ) {
    const pairer = EndpointPairer();
    if (preference.captureId != null || preference.renderId != null) {
      return pairer.select(
        const PairingSnapshot(),
        catalog,
        captureId: preference.captureId,
        renderId: preference.renderId,
      );
    }
    final speaker = pairer.speakerphone(catalog);
    return PairingSnapshot(
      captureId: speaker?.capture?.id,
      renderId: speaker?.render?.id,
    );
  }

  StartReady _attachSession({
    required AudioFormat captureFormat,
    required AudioFormat playbackFormat,
    required SessionPreference preference,
    required BargeInPolicy bargeInPolicy,
    required PairingSnapshot pairing,
    required List<Endpoint> catalog,
  }) {
    final session = Session._(
      platform: _platform,
      captureFormat: captureFormat,
      playbackFormat: playbackFormat,
      preference: preference,
      bargeInPolicy: bargeInPolicy,
      coverageSource: _coverageSource,
      pairing: pairing,
      catalog: catalog,
      onStopped: () => _session = null,
      logger: _logger,
    );
    _session = session;
    return StartReady(session);
  }
}
