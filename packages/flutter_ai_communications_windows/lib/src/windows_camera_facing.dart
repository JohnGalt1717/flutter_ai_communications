import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Facing from advertised name and the Media Foundation symbolic link.
///
/// USB in the link is external unless the name says the camera is built-in.
/// Native C++ uses the same rules.
CameraFacing windowsCameraFacing({
  required String name,
  String symbolicLink = '',
}) {
  final haystack = '${name.toLowerCase()} ${symbolicLink.toLowerCase()}';
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
