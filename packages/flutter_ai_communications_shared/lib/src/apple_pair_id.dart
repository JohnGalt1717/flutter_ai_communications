import 'endpoint.dart';

/// Pair identity for iOS/macOS accessory Endpoints whose capture and render
/// UIDs differ (AirPods HFP vs A2DP).
///
/// [name] is unused; the pair key is the hardware uid token (with `-tsco` /
/// `-tacl` stripped when present). Kept for call-site compatibility.
String applePairId({
  required RouteClass routeClass,
  required String uid,
  required String name,
}) {
  return switch (routeClass) {
    RouteClass.handset => 'handset',
    RouteClass.speakerphone => 'speakerphone',
    RouteClass.bluetooth || RouteClass.wired || RouteClass.car =>
      _hardwareToken(uid),
  };
}

String _hardwareToken(String uid) {
  const suffixes = ['-tsco', '-tacl'];
  for (final suffix in suffixes) {
    if (uid.endsWith(suffix)) {
      return uid.substring(0, uid.length - suffix.length);
    }
  }
  return uid;
}
