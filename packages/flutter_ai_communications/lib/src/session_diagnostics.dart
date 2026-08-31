import 'dart:async';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:logging/logging.dart';

/// Lifecycle phase of a Session. Distinct from [SessionStatus] readiness.
enum SessionLifecycle {
  /// Native graph is starting.
  starting,

  /// Capture and/or playback are running.
  live,

  /// Capture and playback are parked.
  paused,

  /// The Session has ended.
  stopped,
}

/// Route and media observations for hosts and the conformance harness.
///
/// Does not include captured audio bytes.
final class SessionDiagnostics {
  /// Creates a diagnostics snapshot.
  const SessionDiagnostics({
    required this.desired,
    required this.applied,
    required this.observed,
    required this.preferenceControlled,
    required this.lifecycle,
    this.catalog = const [],
    this.selectionGeneration = 0,
    this.routeChangeCause,
    this.captureFrameCount = 0,
    this.recentRms,
    this.lastCaptureAt,
    this.playbackAccepted = 0,
    this.playbackQueued = 0,
    this.playbackRendered = 0,
    this.playbackFlushed = 0,
    this.requestedCaptureFormat,
    this.requestedPlaybackFormat,
    this.nativeCaptureFormat,
    this.nativePlaybackFormat,
    this.edgeCaptureFormat,
    this.edgePlaybackFormat,
    this.captureConversionPath = ConversionPath.identity,
    this.playbackConversionPath = ConversionPath.identity,
    this.formatFailures = const [],
    this.acousticProfile,
    this.baselineStep,
    this.profileConfidence,
    this.captureProcessor,
    this.activeFloor,
  });

  /// Pair selected by Explicit selection or Endpoint preference.
  final PairingSnapshot desired;

  /// Pair most recently sent to the platform.
  final PairingSnapshot applied;

  /// Pair the platform reports is carrying audio.
  final PairingSnapshot observed;

  /// Whether Endpoint preference currently controls the Session.
  final bool preferenceControlled;

  /// Idle catalog snapshot last observed by the Session.
  final List<Endpoint> catalog;

  /// Monotonic generation for start/select/apply.
  final int selectionGeneration;

  /// Why Desired/Applied last changed (`start`, `explicit`, `preference`,
  /// `catalog`, `os`).
  final String? routeChangeCause;

  /// Session lifecycle phase.
  final SessionLifecycle lifecycle;

  /// Capture frames emitted on the public Capture stream.
  final int captureFrameCount;

  /// RMS of the most recent capture frame, if any.
  final double? recentRms;

  /// Timestamp of the most recent capture frame.
  final DateTime? lastCaptureAt;

  /// Playback chunks accepted by [Session.play].
  final int playbackAccepted;

  /// Playback chunks still queued, when the platform reports it.
  final int playbackQueued;

  /// Playback chunks rendered, when the platform reports it.
  final int playbackRendered;

  /// Playback flushes (barge-in or host flush).
  final int playbackFlushed;

  /// Capture Format requested by the host.
  final AudioFormat? requestedCaptureFormat;

  /// Playback Format requested by the host.
  final AudioFormat? requestedPlaybackFormat;

  /// Native capture Format, when negotiated.
  final AudioFormat? nativeCaptureFormat;

  /// Native playback Format, when negotiated.
  final AudioFormat? nativePlaybackFormat;

  /// Capture Format promised on the public Capture stream.
  final AudioFormat? edgeCaptureFormat;

  /// Playback Format promised to [Session.play].
  final AudioFormat? edgePlaybackFormat;

  /// How Native capture relates to the Capture stream.
  final ConversionPath captureConversionPath;

  /// How Native playback relates to [Session.play].
  final ConversionPath playbackConversionPath;

  /// Native Format candidates rejected during negotiation.
  final List<FormatCandidateFailure> formatFailures;

  /// Acoustic profile for the current capture Endpoint.
  final AcousticProfile? acousticProfile;

  /// Baseline step selected from [acousticProfile].
  final int? baselineStep;

  /// How strongly [acousticProfile] is supported.
  final ProfileConfidence? profileConfidence;

  /// Capture processor currently applied to the Capture stream.
  final CaptureProcessor? captureProcessor;

  /// Active Sound floor after Baseline, scale, adaptation, and Isolation.
  final double? activeFloor;

  /// Whether Observed Pair currently matches Desired Pair for present ids.
  bool get observedMatchesDesired {
    final captureOk =
        desired.captureId == null || desired.captureId == observed.captureId;
    final renderOk =
        desired.renderId == null || desired.renderId == observed.renderId;
    return captureOk && renderOk;
  }
}

/// Stable machine codes for structured pipeline [Logger] records.
///
/// Messages are codes and ids only. Hosts map them; the library never
/// emits user-facing copy.
abstract final class PipelineLog {
  /// Logger name for Communications manager and Session pipeline records.
  static const String loggerName = 'CommunicationsManager';

  /// [CommunicationsManager.start] was requested.
  static const String startRequested = 'pipeline.start.requested';

  /// Competing [CommunicationsManager.start] while a Session is live.
  static const String startAlreadyActive = 'pipeline.start.alreadyActive';

  /// Microphone permission was requested or skipped.
  static const String permission = 'pipeline.permission';

  /// Idle catalog was enumerated at start.
  static const String catalog = 'pipeline.catalog';

  /// Preference or Explicit selection resolved Desired Pair.
  static const String preferenceResolved = 'pipeline.preference.resolved';

  /// Bound host Endpoint preference changed.
  static const String preferenceBound = 'pipeline.preference.bound';

  /// Native graph start was attempted.
  static const String nativeStart = 'pipeline.native.start';

  /// Native Formats and Conversion path after negotiation.
  static const String formatNegotiated = 'pipeline.format.negotiated';

  /// Acoustic profile classified for the current capture Endpoint.
  static const String profileClassified = 'pipeline.profile.classified';

  /// Native graph reset under the same Session.
  static const String nativeReset = 'pipeline.native.reset';

  /// Session object attached after native start.
  static const String sessionAttached = 'pipeline.session.attached';

  /// Desired Pair changed.
  static const String desired = 'pipeline.route.desired';

  /// Applied Pair was sent to the platform.
  static const String applied = 'pipeline.route.applied';

  /// Observed Pair arrived from the platform.
  static const String observed = 'pipeline.route.observed';

  /// [SessionStatus] changed.
  static const String status = 'pipeline.status';

  /// Capture frame cadence/RMS (never audio bytes).
  static const String capture = 'pipeline.capture';

  /// Playback accepted, queued, rendered, or flushed.
  static const String playback = 'pipeline.playback';

  /// Isolation state presented to the host (ids only).
  static const String isolation = 'pipeline.isolation';

  /// Session paused.
  static const String paused = 'pipeline.session.paused';

  /// Session resumed.
  static const String resumed = 'pipeline.session.resumed';

  /// Session muted or unmuted.
  static const String mute = 'pipeline.session.mute';

  /// Session ended.
  static const String stopped = 'pipeline.session.stopped';

  /// Builds a structured log line from a code and key/value fields.
  static String line(String code, [Map<String, Object?> fields = const {}]) {
    if (fields.isEmpty) {
      return code;
    }
    final parts = <String>[code];
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value == null) {
        continue;
      }
      parts.add('$key=$value');
    }
    return parts.join(' ');
  }

  /// Parses [PipelineLog.line] records from a [LogRecord].
  static Map<String, String> parse(String message) {
    final out = <String, String>{};
    final parts = message.split(' ');
    if (parts.isEmpty) {
      return out;
    }
    out['code'] = parts.first;
    for (final part in parts.skip(1)) {
      final split = part.indexOf('=');
      if (split <= 0) {
        continue;
      }
      final key = part.substring(0, split);
      if (key == 'code') {
        continue;
      }
      out[key] = part.substring(split + 1);
    }
    return out;
  }

  /// Attaches a subscription that records pipeline [LogRecord]s.
  static StreamSubscription<LogRecord> listen(
    void Function(LogRecord record) onRecord, {
    Logger? logger,
  }) {
    return (logger ?? Logger(loggerName)).onRecord.listen(onRecord);
  }
}
