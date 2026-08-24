import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Maps macOS device metadata to a [RouteClass].
///
/// Built-in speakers/mics are speakerphone. There is no handset on desktop.
RouteClass macosRouteClass({required String name, String transport = ''}) {
  final lowerName = name.toLowerCase();
  final lowerTransport = transport.toLowerCase();
  if (lowerTransport.contains('blue') || lowerName.contains('bluetooth')) {
    return RouteClass.bluetooth;
  }
  if (lowerName.contains('headset') ||
      lowerName.contains('headphone') ||
      lowerName.contains('earphone') ||
      lowerTransport.contains('usb')) {
    return RouteClass.wired;
  }
  if (lowerName.contains('speaker') ||
      lowerName.contains('microphone') ||
      lowerName.contains('built-in') ||
      lowerName.contains('macbook') ||
      lowerTransport.contains('bltn') ||
      lowerTransport.contains('pci')) {
    return RouteClass.speakerphone;
  }
  return RouteClass.wired;
}

/// Pair key for built-in speakerphone Endpoints.
const macosBuiltInPairId = 'built-in';

/// Pair identity shared by a capture/render Endpoint.
String macosPairId({
  required RouteClass routeClass,
  required String id,
  required String name,
  String uid = '',
}) {
  if (routeClass == RouteClass.speakerphone) {
    return macosBuiltInPairId;
  }
  return applePairId(
    routeClass: routeClass,
    uid: uid.isEmpty ? id : uid,
    name: name,
  );
}
