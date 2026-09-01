import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Facing from V4L2 card name and bus_info.
///
/// Native C++ uses the same rules. USB bus_info is external unless the card
/// name says the camera is built-in.
CameraFacing linuxCameraFacing({required String name, String busInfo = ''}) {
  final haystack = '${name.toLowerCase()} ${busInfo.toLowerCase()}';
  if (_hasAny(haystack, const ['front', 'user', 'integrated', 'internal'])) {
    return CameraFacing.user;
  }
  if (_hasAny(haystack, const ['rear', 'back'])) {
    return CameraFacing.environment;
  }
  if (_hasAny(haystack, const ['usb'])) {
    return CameraFacing.external;
  }
  return CameraFacing.unspecified;
}

bool _hasAny(String haystack, List<String> needles) {
  for (final needle in needles) {
    if (haystack.contains(needle)) {
      return true;
    }
  }
  return false;
}
