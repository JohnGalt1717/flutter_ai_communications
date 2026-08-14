/// Microphone permission outcome from the platform.
enum MicrophonePermission {
  /// The host may capture.
  granted,

  /// The user declined.
  denied,

  /// The OS will not allow capture (parental controls, MDM).
  restricted,
}
