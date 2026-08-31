import 'camera_endpoint.dart';
import 'camera_facing.dart';

/// One ordered Camera preference slot.
final class CameraPreferenceEntry {
  /// Creates a preference entry.
  const CameraPreferenceEntry({required this.id, this.enabled = true});

  /// Stable Camera Endpoint id.
  final String id;

  /// Disabled cameras are skipped by automatic resolution.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is CameraPreferenceEntry &&
      other.id == id &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, enabled);
}

/// Host-persisted ordered Camera Endpoint list. Independent of Endpoint preference.
final class CameraPreference {
  /// Creates a Camera preference. Empty [entries] means intelligent default.
  const CameraPreference({this.entries = const []});

  /// Most-preferred first.
  final List<CameraPreferenceEntry> entries;

  /// Whether the host supplied any ordered entries.
  bool get isEmpty => entries.isEmpty;

  /// Resolves a Camera Endpoint. Empty preference uses user-facing, then first.
  CameraEndpoint? resolve(List<CameraEndpoint> catalog) {
    if (catalog.isEmpty) {
      return null;
    }
    for (final entry in entries) {
      if (!entry.enabled) {
        continue;
      }
      for (final camera in catalog) {
        if (camera.id == entry.id) {
          return camera;
        }
      }
    }
    for (final camera in catalog) {
      if (camera.facing == CameraFacing.user) {
        return camera;
      }
    }
    return catalog.first;
  }

  @override
  bool operator ==(Object other) =>
      other is CameraPreference && _sameEntries(other.entries);

  bool _sameEntries(List<CameraPreferenceEntry> other) {
    if (other.length != entries.length) {
      return false;
    }
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);
}
