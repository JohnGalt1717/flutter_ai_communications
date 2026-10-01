import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Maps macOS device metadata to a [RouteClass].
///
/// Built-in speakers/mics are speakerphone from transport `bltn` / `pci`.
/// Do not classify speakerphone from display-name substrings (issue #90).
RouteClass macosRouteClass({required String name, String transport = ''}) {
  final lowerName = name.toLowerCase();
  final lowerTransport = transport.toLowerCase();
  if (lowerTransport.contains('blue') ||
      lowerTransport.contains('blea') ||
      lowerName.contains('bluetooth')) {
    return RouteClass.bluetooth;
  }
  if (lowerName.contains('headset') ||
      lowerName.contains('headphone') ||
      lowerName.contains('earphone') ||
      lowerTransport.contains('usb')) {
    return RouteClass.wired;
  }
  if (lowerTransport.contains('bltn') || lowerTransport.contains('pci')) {
    return RouteClass.speakerphone;
  }
  return RouteClass.wired;
}

/// Pair key for built-in speakerphone Endpoints.
const macosBuiltInPairId = 'built-in';

/// Pair identity from Core Audio hardware metadata (issue #90).
///
/// - Transport `bltn` → [macosBuiltInPairId]
/// - Bluetooth (`blue` / LE): UID with trailing `:input` / `:output` stripped
/// - Otherwise: RelatedDevices clique UIDs sorted and joined with `|`
String macosPairId({
  required RouteClass routeClass,
  required String id,
  required String name,
  String uid = '',
  String transport = '',
  List<String> relatedUids = const [],
}) {
  // [name] is display-only; the pair key is hardware metadata (issue #90).
  final deviceUid = uid.isEmpty ? id : uid;
  final lowerTransport = transport.toLowerCase();
  if (lowerTransport.contains('bltn') ||
      (lowerTransport.isEmpty && routeClass == RouteClass.speakerphone)) {
    return macosBuiltInPairId;
  }
  if (lowerTransport.contains('blue') || lowerTransport.contains('blea')) {
    return macosBluetoothPairKey(deviceUid);
  }
  final clique = <String>{deviceUid, ...relatedUids}.toList()..sort();
  return clique.join('|');
}

/// Bluetooth device UID without a trailing `:input` / `:output` half-marker.
String macosBluetoothPairKey(String uid) {
  if (uid.endsWith(':input')) {
    return uid.substring(0, uid.length - ':input'.length);
  }
  if (uid.endsWith(':output')) {
    return uid.substring(0, uid.length - ':output'.length);
  }
  return uid;
}
