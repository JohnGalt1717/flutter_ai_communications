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
  if (lowerForm == 'car' ||
      lowerName.contains('carplay') ||
      lowerName.contains('android auto')) {
    return RouteClass.car;
  }
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
      lowerName.contains('rdpsource') ||
      lowerName.contains('rdpsink') ||
      lowerName.contains('rdp source') ||
      lowerName.contains('rdp sink') ||
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

/// Pulse `device.form_factor` to Endpoint form factor.
EndpointFormFactor linuxEndpointFormFactor(String formFactor) {
  return switch (formFactor.toLowerCase()) {
    'headset' ||
    'headphone' ||
    'hands-free' ||
    'handsfree' => EndpointFormFactor.headset,
    'speaker' => EndpointFormFactor.speaker,
    'car' => EndpointFormFactor.car,
    _ => EndpointFormFactor.unknown,
  };
}

/// Builds an Endpoint from Pulse / PipeWire catalog fields.
Endpoint linuxEndpointFromPulse({
  required String id,
  required String name,
  required bool isCapture,
  String bus = '',
  String formFactor = '',
  int card = 0xffffffff,
}) {
  final route = linuxRouteClass(name: name, bus: bus, formFactor: formFactor);
  final form = linuxEndpointFormFactor(formFactor);
  return Endpoint(
    id: id,
    name: name,
    routeClass: route,
    isCapture: isCapture,
    pairId: linuxPairId(routeClass: route, id: id, name: name, card: card),
    capabilities: EndpointCapabilities(
      formFactor: form,
      carConnected: route == RouteClass.car || form == EndpointFormFactor.car,
    ),
  );
}
