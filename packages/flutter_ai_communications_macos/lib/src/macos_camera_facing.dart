import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Facing from the advertised camera name when AVFoundation reports none.
///
/// Built-in FaceTime / MacBook cameras face the user. USB capture devices
/// are external. Native enumerate uses the same rules.
CameraFacing macosCameraFacing({required String name}) {
  final haystack = name.toLowerCase();
  if (_hasAny(haystack, const [
    'macbook',
    'imac',
    'facetime',
    'built-in',
    'studio display',
    'continuity',
    'front',
    'user',
  ])) {
    return CameraFacing.user;
  }
  if (_hasAny(haystack, const ['rear', 'back'])) {
    return CameraFacing.environment;
  }
  return CameraFacing.external;
}

/// Overlay name-based facing when native enumerate left it unspecified.
List<CameraEndpoint> overlayMacosCameraFacing(List<CameraEndpoint> cameras) {
  return [
    for (final camera in cameras)
      if (camera.facing == CameraFacing.unspecified)
        CameraEndpoint(
          id: camera.id,
          name: camera.name,
          facing: macosCameraFacing(name: camera.name),
          modes: camera.modes,
        )
      else
        camera,
  ];
}

bool _hasAny(String haystack, List<String> needles) {
  for (final needle in needles) {
    if (haystack.contains(needle)) {
      return true;
    }
  }
  return false;
}
