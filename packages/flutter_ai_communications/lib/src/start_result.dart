part of '../flutter_ai_communications.dart';

/// Outcome of [AudioManager.start]. Expected failures are values.
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
