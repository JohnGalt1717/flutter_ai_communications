import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Maps Pulse / PipeWire device metadata to a [RouteClass].
///
/// Built-in speakers/mics are speakerphone. There is no handset on desktop.
RouteClass linuxRouteClass({
  required String name,
  String bus = '',
  String formFactor = '',
}) {
  final lowerName = name.toLowerCase();
  final lowerBus = bus.toLowerCase();
  final lowerForm = formFactor.toLowerCase();
  if (lowerBus.contains('bluetooth') ||
      lowerForm.contains('headset') && lowerBus.contains('blue') ||
      lowerName.contains('bluetooth')) {
    return RouteClass.bluetooth;
  }
  if (lowerForm == 'headset' ||
      lowerForm == 'headphone' ||
      lowerName.contains('headset') ||
      lowerName.contains('headphone') ||
      lowerBus.contains('usb')) {
    return RouteClass.wired;
  }
  if (lowerForm == 'speaker' ||
      lowerForm == 'microphone' ||
      lowerName.contains('built-in') ||
      lowerName.contains('analog') ||
      lowerBus.contains('pci') ||
      lowerBus.contains('isa')) {
    return RouteClass.speakerphone;
  }
  return RouteClass.wired;
}

/// Pair key for built-in speakerphone Endpoints.
const linuxBuiltInPairId = 'built-in';

/// Pair identity shared by a capture/render Endpoint.
String linuxPairId({
  required RouteClass routeClass,
  required String id,
  required String name,
  int card = 0xffffffff,
}) {
  if (routeClass == RouteClass.speakerphone) {
    return linuxBuiltInPairId;
  }
  if (card != 0xffffffff) {
    return 'card-$card';
  }
  return name.isEmpty ? id : name;
}
