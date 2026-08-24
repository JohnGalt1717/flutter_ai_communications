import 'endpoint.dart';
import 'pairing.dart';

/// One ordered Endpoint preference slot.
final class EndpointPreferenceEntry {
  /// Creates a preference entry.
  const EndpointPreferenceEntry({required this.id, this.enabled = true});

  /// Stable Endpoint id. May remain in the list while unavailable.
  final String id;

  /// Disabled Endpoints are skipped by automatic resolution.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is EndpointPreferenceEntry &&
      other.id == id &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, enabled);
}

/// Host-persisted ordered enabled Endpoint preference.
///
/// Persistence belongs to the host. The Audio manager continuously resolves
/// this list from most to least preferred.
final class EndpointPreference {
  /// Creates an Endpoint preference. Empty [entries] means platform default.
  const EndpointPreference({this.entries = const []});

  /// Most-preferred first. Unavailable ids stay in place and are never guessed.
  final List<EndpointPreferenceEntry> entries;

  /// Whether the host supplied any ordered entries.
  bool get isEmpty => entries.isEmpty;

  /// Deterministic new-user order: Bluetooth/headset, wired, car, speakerphone,
  /// handset.
  static EndpointPreference platformDefault(List<Endpoint> catalog) {
    const order = [
      RouteClass.bluetooth,
      RouteClass.wired,
      RouteClass.car,
      RouteClass.speakerphone,
      RouteClass.handset,
    ];
    final seen = <String>{};
    final entries = <EndpointPreferenceEntry>[];
    for (final routeClass in order) {
      for (final endpoint in catalog) {
        if (endpoint.routeClass != routeClass ||
            seen.contains(endpoint.pairId)) {
          continue;
        }
        seen.add(endpoint.pairId);
        final capture = catalog
            .where((item) => item.pairId == endpoint.pairId && item.isCapture)
            .firstOrNull;
        entries.add(EndpointPreferenceEntry(id: (capture ?? endpoint).id));
      }
    }
    return EndpointPreference(entries: entries);
  }

  @override
  bool operator ==(Object other) =>
      other is EndpointPreference && _sameEntries(other.entries);

  bool _sameEntries(List<EndpointPreferenceEntry> other) {
    if (other.length != entries.length) {
      return false;
    }
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);
}

/// Outcome of resolving Endpoint preference or an Explicit selection.
final class PreferenceResolution {
  /// Creates a resolution.
  const PreferenceResolution({
    required this.desired,
    required this.preferenceControlled,
    this.unresolvedIds = const [],
    this.exhausted = false,
  });

  /// Desired Pair after policy.
  final PairingSnapshot desired;

  /// Whether Endpoint preference currently controls the Session.
  final bool preferenceControlled;

  /// Preference ids that were skipped because they are not in the catalog.
  final List<String> unresolvedIds;

  /// Every automatic candidate was missing, disabled, incomplete, or unusable.
  final bool exhausted;

  @override
  bool operator ==(Object other) =>
      other is PreferenceResolution &&
      other.desired == desired &&
      other.preferenceControlled == preferenceControlled &&
      other.exhausted == exhausted;

  @override
  int get hashCode => Object.hash(desired, preferenceControlled, exhausted);
}

/// Resolves Desired Pair from Endpoint preference and Explicit selection.
final class PreferenceResolver {
  /// Creates a resolver.
  const PreferenceResolver();

  static const _pairer = EndpointPairer();

  /// Resolves the Desired Pair.
  ///
  /// An empty host list uses platform default complete Pairs. A host-supplied
  /// list fills capture and render independently, so a desktop webcam and a
  /// USB render Endpoint can outrank AirPods. Explicit selection may be
  /// split and never falls back while available.
  PreferenceResolution resolve({
    required List<Endpoint> catalog,
    EndpointPreference preference = const EndpointPreference(),
    bool requireCapture = true,
    bool requireRender = true,
    String? explicitCaptureId,
    String? explicitRenderId,
    Set<String> unusablePairIds = const {},
  }) {
    final explicit = _explicit(
      catalog,
      requireCapture: requireCapture,
      requireRender: requireRender,
      explicitCaptureId: explicitCaptureId,
      explicitRenderId: explicitRenderId,
    );
    if (explicit != null) {
      return explicit;
    }

    if (preference.isEmpty) {
      return _walkCompletePairs(
        catalog: catalog,
        entries: EndpointPreference.platformDefault(catalog).entries,
        requireCapture: requireCapture,
        requireRender: requireRender,
        unusablePairIds: unusablePairIds,
      );
    }
    return _fillEdges(
      catalog: catalog,
      entries: preference.entries,
      requireCapture: requireCapture,
      requireRender: requireRender,
      unusablePairIds: unusablePairIds,
    );
  }

  PreferenceResolution _walkCompletePairs({
    required List<Endpoint> catalog,
    required List<EndpointPreferenceEntry> entries,
    required bool requireCapture,
    required bool requireRender,
    required Set<String> unusablePairIds,
  }) {
    final unresolved = <String>[];
    for (final entry in entries) {
      final endpoint = _byId(catalog, entry.id);
      if (endpoint == null) {
        unresolved.add(entry.id);
        continue;
      }
      if (!entry.enabled) {
        continue;
      }
      final pair = _pairer.pairFor(endpoint, catalog);
      if (pair == null || unusablePairIds.contains(pair.id)) {
        continue;
      }
      if (requireCapture && pair.capture == null) {
        continue;
      }
      if (requireRender && pair.render == null) {
        continue;
      }
      return PreferenceResolution(
        desired: PairingSnapshot(
          captureId: pair.capture?.id,
          renderId: pair.render?.id,
        ),
        preferenceControlled: true,
        unresolvedIds: unresolved,
      );
    }
    return PreferenceResolution(
      desired: const PairingSnapshot(),
      preferenceControlled: true,
      unresolvedIds: unresolved,
      exhausted: true,
    );
  }

  PreferenceResolution _fillEdges({
    required List<Endpoint> catalog,
    required List<EndpointPreferenceEntry> entries,
    required bool requireCapture,
    required bool requireRender,
    required Set<String> unusablePairIds,
  }) {
    final unresolved = <String>[];
    String? captureId;
    String? renderId;
    String? capturePairId;
    String? renderPairId;
    for (final entry in entries) {
      final endpoint = _byId(catalog, entry.id);
      if (endpoint == null) {
        unresolved.add(entry.id);
        continue;
      }
      if (!entry.enabled) {
        continue;
      }
      final pair = _pairer.pairFor(endpoint, catalog);
      if (pair != null && unusablePairIds.contains(pair.id)) {
        continue;
      }
      if (endpoint.isCapture && captureId == null) {
        captureId = endpoint.id;
        capturePairId = endpoint.pairId;
      } else if (!endpoint.isCapture && renderId == null) {
        renderId = endpoint.id;
        renderPairId = endpoint.pairId;
      }
      if (captureId == null && pair?.capture != null) {
        captureId = pair!.capture!.id;
        capturePairId = pair.capture!.pairId;
      }
      if (renderId == null && pair?.render != null) {
        renderId = pair!.render!.id;
        renderPairId = pair.render!.pairId;
      }
      final captureReady = !requireCapture || captureId != null;
      final renderReady = !requireRender || renderId != null;
      if (captureReady && renderReady) {
        final split =
            captureId != null &&
            renderId != null &&
            capturePairId != renderPairId;
        return PreferenceResolution(
          desired: PairingSnapshot(
            captureId: captureId,
            renderId: renderId,
            captureOverride: split,
            renderOverride: split,
          ),
          preferenceControlled: true,
          unresolvedIds: unresolved,
        );
      }
    }
    return PreferenceResolution(
      desired: const PairingSnapshot(),
      preferenceControlled: true,
      unresolvedIds: unresolved,
      exhausted: true,
    );
  }

  PreferenceResolution? _explicit(
    List<Endpoint> catalog, {
    required bool requireCapture,
    required bool requireRender,
    required String? explicitCaptureId,
    required String? explicitRenderId,
  }) {
    if (explicitCaptureId == null && explicitRenderId == null) {
      return null;
    }
    final capture = _byId(catalog, explicitCaptureId);
    final render = _byId(catalog, explicitRenderId);
    if (explicitCaptureId != null && capture == null) {
      return null;
    }
    if (explicitRenderId != null && render == null) {
      return null;
    }

    var captureId = capture?.id;
    var renderId = render?.id;
    var captureOverride = false;
    var renderOverride = false;
    if (capture != null && render == null) {
      renderId = _pairer.pairFor(capture, catalog)?.render?.id;
    } else if (render != null && capture == null) {
      captureId = _pairer.pairFor(render, catalog)?.capture?.id;
    } else if (capture != null && render != null) {
      final mates = capture.pairId == render.pairId;
      captureOverride = !mates;
      renderOverride = !mates;
    }
    if (requireCapture && captureId == null) {
      return null;
    }
    if (requireRender && renderId == null) {
      return null;
    }
    return PreferenceResolution(
      desired: PairingSnapshot(
        captureId: captureId,
        renderId: renderId,
        captureOverride: captureOverride,
        renderOverride: renderOverride,
      ),
      preferenceControlled: false,
    );
  }

  Endpoint? _byId(List<Endpoint> catalog, String? id) {
    if (id == null) {
      return null;
    }
    return catalog.where((endpoint) => endpoint.id == id).firstOrNull;
  }
}
