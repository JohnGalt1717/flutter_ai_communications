import 'endpoint.dart';

/// Bluetooth radio identity used to enrich audio Endpoints.
final class BluetoothIdentity {
  /// Creates an identity snapshot.
  const BluetoothIdentity({
    required this.name,
    this.classOfDevice = 0,
    this.address = '',
    this.hints = const [],
  });

  /// Bluetooth alias / advertised name.
  final String name;

  /// Class of Device bitfield from the radio.
  final int classOfDevice;

  /// Optional address string for matching.
  final String address;

  /// Extra tokens from manufacturer data or radio metadata.
  final List<String> hints;
}

/// Maps a Bluetooth Class of Device to a form factor.
///
/// Audio/Video major class 4: headset minors, speaker minors, car audio.
EndpointFormFactor formFactorFromBluetoothClassOfDevice(int classOfDevice) {
  final major = (classOfDevice >> 8) & 0x1f;
  if (major != 4) {
    return EndpointFormFactor.unknown;
  }
  final minor = (classOfDevice >> 2) & 0x3f;
  return switch (minor) {
    1 || 2 || 4 || 6 || 7 => EndpointFormFactor.headset,
    5 || 10 || 15 => EndpointFormFactor.speaker,
    8 => EndpointFormFactor.car,
    _ => EndpointFormFactor.unknown,
  };
}

/// Copies Bluetooth alias and form factor onto matching Endpoints.
///
/// Empty [devices] (denied or unavailable) leaves names unchanged.
List<Endpoint> mergeBluetoothIdentity(
  List<Endpoint> endpoints,
  List<BluetoothIdentity> devices,
) {
  if (devices.isEmpty) {
    return endpoints;
  }
  return [
    for (final endpoint in endpoints) _mergeOne(endpoint, devices) ?? endpoint,
  ];
}

Endpoint? _mergeOne(Endpoint endpoint, List<BluetoothIdentity> devices) {
  if (endpoint.routeClass != RouteClass.bluetooth &&
      endpoint.routeClass != RouteClass.car) {
    return null;
  }
  BluetoothIdentity? match;
  for (final device in devices) {
    if (_namesOverlap(endpoint.name, device.name) ||
        _addressesOverlap(endpoint.id, device.address)) {
      match = device;
      break;
    }
  }
  if (match == null) {
    return null;
  }
  final formFactor = formFactorFromBluetoothClassOfDevice(match.classOfDevice);
  final hints = [
    if (match.name.isNotEmpty) match.name,
    for (final hint in match.hints)
      if (hint.isNotEmpty && hint != match.name) hint,
  ];
  return Endpoint(
    id: endpoint.id,
    name: endpoint.name,
    routeClass: endpoint.routeClass,
    isCapture: endpoint.isCapture,
    pairId: endpoint.pairId,
    identityHints: hints,
    capabilities: EndpointCapabilities(
      aec: endpoint.capabilities.aec,
      ns: endpoint.capabilities.ns,
      agc: endpoint.capabilities.agc,
      formFactor: formFactor == EndpointFormFactor.unknown
          ? endpoint.capabilities.formFactor
          : formFactor,
      carConnected:
          endpoint.capabilities.carConnected ||
          formFactor == EndpointFormFactor.car,
    ),
  );
}

bool _namesOverlap(String left, String right) {
  final a = _normalize(left);
  final b = _normalize(right);
  if (a.length < 4 || b.length < 4) {
    return false;
  }
  return a.contains(b) || b.contains(a);
}

bool _addressesOverlap(String endpointId, String address) {
  if (address.isEmpty) {
    return false;
  }
  final needle = _hexOnly(address);
  if (needle.length < 12) {
    return false;
  }
  return _hexOnly(endpointId).contains(needle);
}

String _normalize(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

String _hexOnly(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
}
