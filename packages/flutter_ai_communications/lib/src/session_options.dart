import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Host preference passed to [CommunicationsManager.start].
///
/// [endpoints] is the ordered enabled Endpoint preference. [captureId] and
/// [renderId] are an optional Explicit selection for this Session only.
final class SessionPreference {
  /// Creates a start preference.
  const SessionPreference({
    this.captureId,
    this.renderId,
    this.soundFloor,
    this.processor,
    this.noiseCancelling = true,
    this.endpoints = const EndpointPreference(),
  });

  /// Explicit capture Endpoint id for this Session, if any.
  final String? captureId;

  /// Explicit render Endpoint id for this Session, if any.
  final String? renderId;

  /// Fixed sound floor, or `null` for adaptive. `0` is pass-through.
  /// Ignored when [processor] is set.
  final double? soundFloor;

  /// Capture processor for this Session. When omitted, [soundFloor] selects
  /// adaptive, fixed, or pass-through.
  final CaptureProcessor? processor;

  /// Whether the Session asks the platform for AEC/NS/AGC and Isolation.
  ///
  /// Isolation is user-chosen. When it is off, the Session emits
  /// [IsolationState.required] so the host can prompt. If Isolation stays
  /// off or is unavailable (macOS), the Session still starts and raises
  /// the adaptive Sound floor. Hosts own every prompt string.
  final bool noiseCancelling;

  /// Ordered enabled Endpoint preference. Empty means platform default or the
  /// preference bound on the Audio manager.
  final EndpointPreference endpoints;
}

/// Whether barge-in is local or left to remote VAD.
enum BargeInPolicy { local, remoteVad }

/// Active audio edges of a Session. Camera send is orthogonal ([CommunicationsManager.start]
/// `cameraSend`).
enum SessionDirection {
  /// Capture only. Does not acquire playback resources.
  captureOnly,

  /// Playback only. Does not request the microphone.
  playbackOnly,

  /// Capture and playback.
  duplex,

  /// No audio edges (video-only or screen-only).
  none;

  /// Whether this direction captures.
  bool get hasCapture =>
      this != SessionDirection.playbackOnly && this != SessionDirection.none;

  /// Whether this direction plays.
  bool get hasPlayback =>
      this != SessionDirection.captureOnly && this != SessionDirection.none;
}

/// Start-able description of a Session. Readable from a live Session.
final class SessionSettings {
  /// Creates Session settings.
  const SessionSettings({
    this.direction = SessionDirection.duplex,
    this.cameraSend = false,
    this.captureFormat,
    this.playbackFormat,
    this.videoFormat,
    this.preference = const SessionPreference(),
    this.cameraPreference = const CameraPreference(),
    this.cameraId,
    this.videoProcessor = const NoneVideoProcessor(),
    this.muted = false,
    this.cameraEnabled = true,
    this.purpose,
    this.bargeInPolicy = BargeInPolicy.local,
  });

  /// Audio edges.
  final SessionDirection direction;

  /// Whether the Session should send camera.
  final bool cameraSend;

  /// Capture Format.
  final AudioFormat? captureFormat;

  /// Playback Format.
  final AudioFormat? playbackFormat;

  /// Requested Video Format.
  final VideoFormat? videoFormat;

  /// Audio preference and explicit picks.
  final SessionPreference preference;

  /// Camera preference.
  final CameraPreference cameraPreference;

  /// Explicit camera id.
  final String? cameraId;

  /// Video processor. v1 is none.
  final VideoProcessor videoProcessor;

  /// Whether to start muted.
  final bool muted;

  /// Whether the camera is enabled (not Camera-off).
  final bool cameraEnabled;

  /// Session purpose.
  final String? purpose;

  /// Barge-in policy.
  final BargeInPolicy bargeInPolicy;
}
