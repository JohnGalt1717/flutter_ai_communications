part of '../flutter_ai_communications.dart';

/// Outcome of [CommunicationsManager.start]. Expected failures are values.
sealed class StartResult {
  const StartResult();
}

/// A Session is live.
final class StartReady extends StartResult {
  /// Creates a ready result.
  const StartReady(this.session);

  /// The live Session.
  final Session session;
}

/// The user declined the microphone.
final class StartDenied extends StartResult {
  /// Creates a denied result.
  const StartDenied();
}

/// The OS will not allow capture.
final class StartRestricted extends StartResult {
  /// Creates a restricted result.
  const StartRestricted();
}

/// No usable capture Endpoint.
final class StartUnavailable extends StartResult {
  /// Creates an unavailable result.
  const StartUnavailable();
}

/// This Audio manager already has a live Session.
final class StartAlreadyActive extends StartResult {
  /// Creates an already-active result.
  const StartAlreadyActive({this.purpose});

  /// Purpose of the live Session that must be ended first.
  final String? purpose;
}

/// The native graph or permission request failed unexpectedly.
final class StartFailed extends StartResult {
  /// Creates a failed result.
  const StartFailed([this.cause]);

  /// Optional underlying cause.
  final Object? cause;
}

/// Outcome of [CommunicationsManager.startCameraPreview].
sealed class PreviewStartResult {
  /// Creates a preview result.
  const PreviewStartResult();
}

/// Camera preview is live.
final class PreviewReady extends PreviewStartResult {
  /// Creates a ready preview.
  const PreviewReady(this.preview);

  /// The live Camera preview.
  final CameraPreview preview;
}

/// The Session is still sending video. Camera-off first.
final class PreviewBlocked extends PreviewStartResult {
  /// Creates a blocked result.
  const PreviewBlocked();
}

/// Camera preview could not start.
final class PreviewFailed extends PreviewStartResult {
  /// Creates a failed result.
  const PreviewFailed([this.cause]);

  /// Optional cause.
  final Object? cause;
}

/// Outcome of [Session.beginScreenPick].
sealed class ScreenPickResult {
  /// Creates a pick result.
  const ScreenPickResult();
}

/// Screen pick is open. Thumbs may be empty when permission was denied.
final class ScreenPickReady extends ScreenPickResult {
  /// Creates a ready pick.
  const ScreenPickReady({this.previewsGranted = true});

  /// Whether Screen previews are available.
  final bool previewsGranted;
}

/// Lobby Session cannot open Screen pick.
final class ScreenPickBlocked extends ScreenPickResult {
  /// Creates a blocked pick.
  const ScreenPickBlocked();
}

/// Screen pick could not start.
final class ScreenPickFailed extends ScreenPickResult {
  /// Creates a failed pick.
  const ScreenPickFailed([this.cause]);

  /// Optional cause.
  final Object? cause;
}

/// Outcome of [Session.startScreenShare].
sealed class ScreenShareResult {
  /// Creates a share result.
  const ScreenShareResult();
}

/// Screen send is live.
final class ScreenShareReady extends ScreenShareResult {
  /// Creates a ready share.
  const ScreenShareReady();
}

/// The user declined screen recording.
final class ScreenShareDenied extends ScreenShareResult {
  /// Creates a denied result.
  const ScreenShareDenied();
}

/// The OS will not allow screen capture.
final class ScreenShareRestricted extends ScreenShareResult {
  /// Creates a restricted result.
  const ScreenShareRestricted();
}

/// No matching Screen source, or the graph could not start.
final class ScreenShareUnavailable extends ScreenShareResult {
  /// Creates an unavailable result.
  const ScreenShareUnavailable();
}

/// Lobby Session cannot start screen send.
final class ScreenShareBlocked extends ScreenShareResult {
  /// Creates a blocked result.
  const ScreenShareBlocked();
}

/// Screen send failed unexpectedly.
final class ScreenShareFailed extends ScreenShareResult {
  /// Creates a failed result.
  const ScreenShareFailed([this.cause]);

  /// Optional cause.
  final Object? cause;
}

/// Outcome of [Session.setVideoProcessor] / [CameraPreview.setVideoProcessor].
sealed class ProcessorSetResult {
  /// Creates a processor result.
  const ProcessorSetResult();
}

/// The processor is running on the Production video path.
final class ProcessorReady extends ProcessorSetResult {
  /// Creates a ready result.
  const ProcessorReady(this.processor);

  /// Applied processor.
  final VideoProcessor processor;
}

/// The still or intensity was invalid, or the Session / Camera preview is
/// stopped. Previous processor stays when the graph is still live.
final class ProcessorInvalid extends ProcessorSetResult {
  /// Creates an invalid result.
  const ProcessorInvalid();
}

/// Native segmentation is unavailable. Processor is none.
final class ProcessorUnavailable extends ProcessorSetResult {
  /// Creates an unavailable result.
  const ProcessorUnavailable();
}

/// Outcome of [Session.captureStill] / [Session.captureScreenStill].
sealed class StillResult {
  /// Creates a still result.
  const StillResult();
}

/// One native JPEG/PNG sample of a Production video path.
final class StillReady extends StillResult {
  /// Creates a ready still.
  const StillReady(
    this.bytes, {
    required this.width,
    required this.height,
    this.mime = 'image/jpeg',
  });

  /// Encoded still bytes.
  final Uint8List bytes;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// `image/jpeg` or `image/png`.
  final String mime;
}

/// The Production video path is not feeding. Fail closed.
final class StillUnavailable extends StillResult {
  /// Creates an unavailable still.
  const StillUnavailable();
}

/// Native grab failed unexpectedly.
final class StillFailed extends StillResult {
  /// Creates a failed still.
  const StillFailed([this.cause]);

  /// Optional underlying cause.
  final Object? cause;
}
