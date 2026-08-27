/// Hardware form factor when the platform reports one.
enum EndpointFormFactor {
  /// Unknown or unreported.
  unknown,

  /// Near-mouth headset or earbuds.
  headset,

  /// Loudspeaker.
  speaker,

  /// Phone receiver.
  handset,

  /// Vehicle audio.
  car,
}

/// Native capability evidence on an Endpoint.
final class EndpointCapabilities {
  /// Creates capability evidence.
  const EndpointCapabilities({
    this.aec = false,
    this.ns = false,
    this.agc = false,
    this.formFactor = EndpointFormFactor.unknown,
    this.carConnected = false,
  });

  /// Active acoustic echo cancellation.
  final bool aec;

  /// Active noise suppression.
  final bool ns;

  /// Active automatic gain control.
  final bool agc;

  /// Reported form factor, when known.
  final EndpointFormFactor formFactor;

  /// Independent car/transport evidence (CarPlay / Android Auto).
  final bool carConnected;

  /// Whether any native processing or form factor is verified.
  bool get hasVerifiedNative =>
      aec ||
      ns ||
      agc ||
      formFactor != EndpointFormFactor.unknown ||
      carConnected;

  @override
  bool operator ==(Object other) =>
      other is EndpointCapabilities &&
      other.aec == aec &&
      other.ns == ns &&
      other.agc == agc &&
      other.formFactor == formFactor &&
      other.carConnected == carConnected;

  @override
  int get hashCode => Object.hash(aec, ns, agc, formFactor, carConnected);
}

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
    this.capabilities = const EndpointCapabilities(),
    this.identityHints = const [],
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

  /// Native capability evidence used for Acoustic-profile classification.
  final EndpointCapabilities capabilities;

  /// Extra names from the OS (Bluetooth alias, manufacturer) used only for
  /// Acoustic-profile matching. Empty when the user denied Bluetooth access.
  final List<String> identityHints;

  @override
  bool operator ==(Object other) =>
      other is Endpoint &&
      other.id == id &&
      other.name == name &&
      other.routeClass == routeClass &&
      other.isCapture == isCapture &&
      other.pairId == pairId &&
      other.capabilities == capabilities &&
      _sameHints(other.identityHints, identityHints);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    routeClass,
    isCapture,
    pairId,
    capabilities,
    Object.hashAll(identityHints),
  );

  @override
  String toString() =>
      'Endpoint($id, $name, ${routeClass.name}, capture: $isCapture)';
}

bool _sameHints(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
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
