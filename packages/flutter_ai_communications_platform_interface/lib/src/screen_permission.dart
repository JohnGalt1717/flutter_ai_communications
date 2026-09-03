/// Screen-recording permission outcome from the platform.
enum ScreenPermission {
  /// The host may capture a Screen source.
  granted,

  /// The user declined.
  denied,

  /// The OS will not allow capture (policy, MDM).
  restricted,
}
