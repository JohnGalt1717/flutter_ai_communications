/// Host preference passed only to [AudioManager.start].
final class SessionPreference {
  /// Creates a start preference.
  const SessionPreference({this.captureId, this.renderId, this.soundFloor});

  /// Preferred capture Endpoint id.
  final String? captureId;

  /// Preferred render Endpoint id.
  final String? renderId;

  /// Fixed sound floor, or `null` for adaptive.
  final double? soundFloor;
}

/// Whether barge-in is local or left to remote VAD.
enum BargeInPolicy { local, remoteVad }
