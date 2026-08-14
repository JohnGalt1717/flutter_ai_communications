/// iOS Isolation detection.
enum IsolationState {
  /// Not yet known.
  unknown,

  /// Isolation is on.
  on,

  /// Isolation is off.
  off,

  /// This platform cannot detect Isolation.
  unavailable,
}

/// Isolation signal for the host UI. No user-facing copy.
final class IsolationEvent {
  /// Creates an Isolation event.
  const IsolationEvent(this.state);

  /// Current Isolation state.
  final IsolationState state;

  @override
  bool operator ==(Object other) =>
      other is IsolationEvent && other.state == state;

  @override
  int get hashCode => state.hashCode;
}
