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

/// Whether a Core Audio device belongs in the Endpoint catalog.
///
/// Virtual (`virt`), aggregate (`grup`), and auto-aggregate (`auto`)
/// transports are software devices. Hidden devices are omitted the same way.
bool macosIsCatalogEndpoint({
  required String name,
  String transport = '',
  bool hidden = false,
}) {
  if (hidden) {
    return false;
  }
  final lowerTransport = transport.toLowerCase().trim();
  if (lowerTransport == 'virt' ||
      lowerTransport == 'grup' ||
      lowerTransport == 'auto') {
    return false;
  }
  final lowerName = name.toLowerCase();
  const blocked = [
    'microsoft teams audio',
    'caddefaultdeviceaggregate',
    'zoomaudio',
    'blackhole',
    'soundflower',
    'vb-audio',
    'multi-output device',
  ];
  for (final needle in blocked) {
    if (lowerName.contains(needle)) {
      return false;
    }
  }
  if (lowerName.contains('loopback')) {
    return false;
  }
  return true;
}

/// Pair key for built-in speakerphone Endpoints.
const macosBuiltInPairId = 'built-in';

/// Pair identity from Core Audio hardware metadata (issue #90).
///
/// - Transport `bltn` / `pci` → [macosBuiltInPairId]
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
      lowerTransport.contains('pci') ||
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
