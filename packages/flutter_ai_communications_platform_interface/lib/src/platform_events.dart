/// Phone-call or other audio-focus state.
enum AudioFocusState {
  /// This Session may render and capture.
  active,

  /// The OS interrupted this Session (phone call, Siri, etc.).
  interrupted,
}

/// Native audio-path hint. Combined with the host [CoverageSource] in Session.
final class CoverageHint {
  /// Creates a path hint.
  const CoverageHint({required this.alive, this.reason});

  /// The communications route is usable.
  const CoverageHint.ok() : alive = true, reason = null;

  /// The communications route is dead.
  const CoverageHint.dead({this.reason = 'pathDead'}) : alive = false;

  /// Whether the path is usable.
  final bool alive;

  /// Optional machine reason (`pathDead`, `airplane`).
  final String? reason;
}

/// OS-forced capture/render change.
final class OsRouteChange {
  /// Creates an OS-forced route change.
  const OsRouteChange({this.captureId, this.renderId});

  /// Forced capture Endpoint id.
  final String? captureId;

  /// Forced render Endpoint id.
  final String? renderId;
}
