import 'camera_facing.dart';
import 'video_format.dart';

/// One camera the OS exposes, with the richest metadata the platform can give.
final class CameraEndpoint {
  /// Creates a Camera Endpoint. Missing fields are null and unused.
  const CameraEndpoint({
    required this.id,
    required this.name,
    this.facing = CameraFacing.unspecified,
    this.modes = const [],
  });

  /// Stable camera id.
  final String id;

  /// Advertised name.
  final String name;

  /// Facing when the platform reports it.
  final CameraFacing facing;

  /// Native modes when the platform reports them.
  final List<VideoFormat> modes;

  @override
  bool operator ==(Object other) =>
      other is CameraEndpoint &&
      other.id == id &&
      other.name == name &&
      other.facing == facing &&
      _sameModes(other.modes);

  bool _sameModes(List<VideoFormat> other) {
    if (other.length != modes.length) {
      return false;
    }
    for (var i = 0; i < modes.length; i++) {
      if (modes[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, name, facing, Object.hashAll(modes));
}
