/// Communications role of an Endpoint.
enum RouteClass {
  /// Phone receiver.
  handset,

  /// Built-in loudspeaker.
  speakerphone,

  /// Bluetooth headset or speaker.
  bluetooth,

  /// Wired headset.
  wired,

  /// Vehicle audio.
  car,
}

/// One capture or render device the OS exposes.
final class Endpoint {
  /// Creates an Endpoint.
  ///
  /// [pairId] is the hardware identity that links capture and render. When
  /// omitted, [name] is the Pair key.
  const Endpoint({
    required this.id,
    required String name,
    required this.routeClass,
    required this.isCapture,
    String? pairId,
  }) : name = name,
       pairId = pairId ?? name;

  /// Stable platform id.
  final String id;

  /// Display name from the OS.
  final String name;

  /// Communications role.
  final RouteClass routeClass;

  /// Whether this Endpoint captures.
  final bool isCapture;

  /// Hardware identity shared by a capture/render Pair.
  final String pairId;

  @override
  bool operator ==(Object other) =>
      other is Endpoint &&
      other.id == id &&
      other.name == name &&
      other.routeClass == routeClass &&
      other.isCapture == isCapture &&
      other.pairId == pairId;

  @override
  int get hashCode => Object.hash(id, name, routeClass, isCapture, pairId);

  @override
  String toString() =>
      'Endpoint($id, $name, ${routeClass.name}, capture: $isCapture)';
}

/// A linked capture Endpoint and render Endpoint.
final class Pair {
  /// Creates a Pair.
  const Pair({required this.id, this.capture, this.render});

  /// Hardware identity.
  final String id;

  /// Capture side, if present in the catalog.
  final Endpoint? capture;

  /// Render side, if present in the catalog.
  final Endpoint? render;
}
