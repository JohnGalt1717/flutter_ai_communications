import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Maps Windows device metadata to a [RouteClass].
///
/// Built-in speakers/mics are speakerphone. There is no handset on desktop.
RouteClass windowsRouteClass({
  required String name,
  String enumerator = '',
}) {
  final lowerName = name.toLowerCase();
  final lowerEnumerator = enumerator.toLowerCase();
  if (lowerEnumerator.contains('bth') ||
      lowerEnumerator.contains('bluetooth') ||
      lowerName.contains('bluetooth')) {
    return RouteClass.bluetooth;
  }
  if (lowerName.contains('headset') ||
      lowerName.contains('headphone') ||
      lowerName.contains('earphone') ||
      lowerEnumerator.contains('usb') ||
      lowerEnumerator.contains('hdmaudbus')) {
    return RouteClass.wired;
  }
  if (lowerName.contains('speaker') ||
      lowerName.contains('microphone') ||
      lowerName.contains('mic ') ||
      lowerEnumerator.contains('root') ||
      lowerEnumerator.contains('hdaudio') ||
      lowerEnumerator.contains('mmdevapi')) {
    return RouteClass.speakerphone;
  }
  return RouteClass.wired;
}

/// Pair key for built-in speakerphone Endpoints.
const windowsBuiltInPairId = 'built-in';

/// Pair identity shared by a capture/render Endpoint.
String windowsPairId({
  required RouteClass routeClass,
  required String id,
  required String name,
  String containerId = '',
}) {
  if (routeClass == RouteClass.speakerphone) {
    return windowsBuiltInPairId;
  }
  if (containerId.isNotEmpty) {
    return containerId;
  }
  return name.isEmpty ? id : name;
}
