import 'endpoint.dart';

/// Pair identity for iOS/macOS accessory Endpoints whose capture and render
/// UIDs differ (AirPods HFP vs A2DP).
String applePairId({
  required RouteClass routeClass,
  required String uid,
  required String name,
}) {
  return switch (routeClass) {
    RouteClass.handset => 'handset',
    RouteClass.speakerphone => 'speakerphone',
    RouteClass.bluetooth || RouteClass.wired || RouteClass.car =>
      _normalizedAccessoryName(name).isEmpty
          ? uid
          : _normalizedAccessoryName(name),
  };
}

String _normalizedAccessoryName(String name) {
  var normalized = name.trim().toLowerCase();
  const suffixes = [
    ' microphone',
    ' mic',
    ' speaker',
    ' headphones',
    ' headset',
  ];
  for (final suffix in suffixes) {
    if (normalized.endsWith(suffix)) {
      normalized = normalized
          .substring(0, normalized.length - suffix.length)
          .trim();
    }
  }
  return normalized;
}
