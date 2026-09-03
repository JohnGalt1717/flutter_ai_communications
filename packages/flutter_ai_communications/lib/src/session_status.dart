/// Severity of a [SessionStatus]. Hosts map this to product UI.
enum StatusSeverity {
  /// The reported condition succeeded.
  success,

  /// The Session remains usable, with a condition the host may surface.
  warning,

  /// The reported condition failed.
  error,
}

/// Whether the host or Session can recover from a [SessionStatus].
enum StatusRecoverability {
  /// No recovery path.
  none,

  /// The Session may recover without host action.
  automatic,

  /// The host must act (end Session, retry, grant permission).
  hostAction,

  /// The user must act through host UI.
  userAction,
}

/// Whether the Session can usefully continue.
enum StatusUsability {
  /// Capture and/or playback are meeting the Session direction.
  usable,

  /// The Session continues with a reduced guarantee.
  degraded,

  /// The Session cannot usefully continue.
  unusable,
}

/// Stable machine code for a [SessionStatus]. No user-facing copy.
enum SessionStatusCode {
  /// Graph and policy are starting.
  starting,

  /// Applicable readiness checks have passed.
  ready,

  /// No complete usable Pair remains.
  noUsablePair,

  /// Desired Pair was applied and Observed Pair is pending or converging.
  routeConverging,

  /// Observed Pair does not match Desired Pair.
  routeMismatch,

  /// Capture frames are arriving for a capture Session.
  captureLive,

  /// Capture frames have stalled.
  captureStalled,

  /// Playback graph is ready for a playback Session.
  playbackReady,

  /// Audio focus interrupted the Session.
  interrupted,

  /// The Session is paused.
  paused,

  /// The Session has ended.
  stopped,

  /// Native Format conversion is in use at a Session edge.
  formatConverted,

  /// Video is not running (denied, restricted, none, or no mode).
  videoNotRunning,
}

/// What the host or user must do, if anything. No user-facing copy.
enum SessionAction {
  /// Nothing required.
  none,

  /// Wait for an in-flight Session transition.
  wait,

  /// End the active Session before starting another.
  endSession,

  /// Request or grant microphone permission.
  grantPermission,

  /// Choose a Pair, or return from Explicit selection to preference.
  selectPair,

  /// Retry the failed operation.
  retry,
}

/// Structured current readiness or failure state.
final class SessionStatus {
  /// Creates a status snapshot.
  const SessionStatus({
    required this.severity,
    required this.code,
    required this.recoverability,
    required this.usability,
    required this.action,
    this.purpose,
    this.generation = 0,
    this.attempt = 0,
    this.maxAttempts = 0,
  });

  /// Starting status before observation.
  const SessionStatus.starting({this.purpose, this.generation = 0})
    : severity = StatusSeverity.warning,
      code = SessionStatusCode.starting,
      recoverability = StatusRecoverability.automatic,
      usability = StatusUsability.degraded,
      action = SessionAction.wait,
      attempt = 0,
      maxAttempts = 0;

  /// Ready status.
  const SessionStatus.ready({this.purpose, this.generation = 0})
    : severity = StatusSeverity.success,
      code = SessionStatusCode.ready,
      recoverability = StatusRecoverability.none,
      usability = StatusUsability.usable,
      action = SessionAction.none,
      attempt = 0,
      maxAttempts = 0;

  /// Video is not running; the Session may still be usable for audio.
  const SessionStatus.videoNotRunning({this.purpose, this.generation = 0})
    : severity = StatusSeverity.warning,
      code = SessionStatusCode.videoNotRunning,
      recoverability = StatusRecoverability.hostAction,
      usability = StatusUsability.usable,
      action = SessionAction.none,
      attempt = 0,
      maxAttempts = 0;

  /// No usable Pair remains.
  const SessionStatus.noUsablePair({this.purpose, this.generation = 0})
    : severity = StatusSeverity.error,
      code = SessionStatusCode.noUsablePair,
      recoverability = StatusRecoverability.hostAction,
      usability = StatusUsability.unusable,
      action = SessionAction.selectPair,
      attempt = 0,
      maxAttempts = 0;

  /// Success, warning, or error.
  final StatusSeverity severity;

  /// Stable machine code.
  final SessionStatusCode code;

  /// Whether recovery is possible.
  final StatusRecoverability recoverability;

  /// Whether the Session remains usable.
  final StatusUsability usability;

  /// Required host or user action.
  final SessionAction action;

  /// Active Session purpose, when known.
  final String? purpose;

  /// Selection generation that produced this status.
  final int generation;

  /// Current bounded attempt, when applicable.
  final int attempt;

  /// Maximum bounded attempts, when applicable.
  final int maxAttempts;

  @override
  bool operator ==(Object other) =>
      other is SessionStatus &&
      other.severity == severity &&
      other.code == code &&
      other.recoverability == recoverability &&
      other.usability == usability &&
      other.action == action &&
      other.purpose == purpose &&
      other.generation == generation &&
      other.attempt == attempt &&
      other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(
    severity,
    code,
    recoverability,
    usability,
    action,
    purpose,
    generation,
    attempt,
    maxAttempts,
  );
}
