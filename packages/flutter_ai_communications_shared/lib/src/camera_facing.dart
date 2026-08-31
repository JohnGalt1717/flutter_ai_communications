/// Facing metadata on a Camera Endpoint. Missing on a platform is unspecified.
enum CameraFacing {
  /// User-facing / front camera.
  user,

  /// World-facing / back camera.
  environment,

  /// USB or other external camera.
  external,

  /// Platform did not report facing.
  unspecified,
}
