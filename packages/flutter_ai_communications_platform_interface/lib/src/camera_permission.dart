/// Camera permission outcome from the platform.
enum CameraPermission {
  /// The host may capture video.
  granted,

  /// The user declined.
  denied,

  /// The OS will not allow capture (parental controls, MDM).
  restricted,
}
