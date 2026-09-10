import 'endpoint.dart';
import 'pairing.dart';

/// One capture slot on an Endpoint preference row.
final class EndpointPreferenceCapture {
  /// Creates a capture slot.
  const EndpointPreferenceCapture({required this.id, this.enabled = true});

  /// Stable capture Endpoint id. May remain while unavailable.
  final String id;

  /// Disabled slots are skipped by automatic resolution.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is EndpointPreferenceCapture &&
      other.id == id &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, enabled);
}

/// One ordered render row with an ordered capture list.
final class EndpointPreferenceEntry {
  /// Creates a preference row. Persist only when [captures] is not empty.
  const EndpointPreferenceEntry({
    required this.renderId,
    this.captures = const [],
    this.enabled = true,
  });

  /// Stable render Endpoint id. May remain in the list while unavailable.
  final String renderId;

  /// Most-preferred capture first. The same capture id may appear on many rows.
  final List<EndpointPreferenceCapture> captures;

  /// Disabled rows are skipped by automatic resolution.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is EndpointPreferenceEntry &&
      other.renderId == renderId &&
      other.enabled == enabled &&
      _sameCaptures(other.captures);

  bool _sameCaptures(List<EndpointPreferenceCapture> other) {
    if (other.length != captures.length) {
      return false;
    }
    for (var i = 0; i < captures.length; i++) {
      if (captures[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(renderId, enabled, Object.hashAll(captures));
}

/// A Desired Pair combination that failed Route convergence this Session.
final class UnusableCombination {
  /// Creates an unusable combination.
  const UnusableCombination({this.renderId, this.captureId});

  /// Render Endpoint id, if the Desired Pair had one.
  final String? renderId;

  /// Capture Endpoint id, if the Desired Pair had one.
  final String? captureId;

  @override
  bool operator ==(Object other) =>
      other is UnusableCombination &&
      other.renderId == renderId &&
      other.captureId == captureId;

  @override
  int get hashCode => Object.hash(renderId, captureId);
}

/// Host-persisted ordered render Endpoints, each with an ordered capture list.
///
/// Persistence belongs to the host. The Communications manager continuously
/// resolves this list from most to least preferred.
final class EndpointPreference {
  /// Creates an Endpoint preference. Empty [entries] means platform default.
  const EndpointPreference({this.entries = const []});

  /// Most-preferred render row first. Unavailable ids stay and are never guessed.
  final List<EndpointPreferenceEntry> entries;

  /// Whether the host supplied any ordered entries.
  bool get isEmpty => entries.isEmpty;

  /// Deterministic new-user order: complete hardware Pairs by Bluetooth,
  /// wired, car, speakerphone, handset. Capture list is the hardware mate.
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
        final capture = catalog
            .where((item) => item.pairId == endpoint.pairId && item.isCapture)
            .firstOrNull;
        final render = catalog
            .where((item) => item.pairId == endpoint.pairId && !item.isCapture)
            .firstOrNull;
        if (capture == null || render == null) {
          continue;
        }
        seen.add(endpoint.pairId);
        entries.add(
          EndpointPreferenceEntry(
            renderId: render.id,
            captures: [EndpointPreferenceCapture(id: capture.id)],
          ),
        );
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
  /// An empty host list uses platform-default complete Pairs. A host list
  /// walks render rows, then each row's capture list. Explicit render stays
  /// while that render is available; capture is completed from that row,
  /// else the hardware Pair, else a capture-only walk of the lists.
  PreferenceResolution resolve({
    required List<Endpoint> catalog,
    EndpointPreference preference = const EndpointPreference(),
    bool requireCapture = true,
    bool requireRender = true,
    String? explicitCaptureId,
    String? explicitRenderId,
    Set<UnusableCombination> unusableCombinations = const {},
  }) {
    final entries = preference.isEmpty
        ? EndpointPreference.platformDefault(catalog).entries
        : preference.entries;
    final explicit = _explicit(
      catalog,
      entries: entries,
      requireCapture: requireCapture,
      requireRender: requireRender,
      explicitCaptureId: explicitCaptureId,
      explicitRenderId: explicitRenderId,
      unusableCombinations: unusableCombinations,
    );
    if (explicit != null) {
      return explicit;
    }
    return _walkRows(
      catalog: catalog,
      entries: entries,
      requireCapture: requireCapture,
      requireRender: requireRender,
      unusableCombinations: unusableCombinations,
      catalogFallback: preference.isEmpty,
    );
  }

  PreferenceResolution _walkRows({
    required List<Endpoint> catalog,
    required List<EndpointPreferenceEntry> entries,
    required bool requireCapture,
    required bool requireRender,
    required Set<UnusableCombination> unusableCombinations,
    required bool catalogFallback,
    List<String>? unresolved,
  }) {
    final skipped = unresolved ?? <String>[];
    for (final entry in entries) {
      if (!entry.enabled) {
        continue;
      }
      final render = _byId(catalog, entry.renderId);
      if (render == null) {
        skipped.add(entry.renderId);
        if (requireRender) {
          continue;
        }
      } else if (render.isCapture) {
        skipped.add(entry.renderId);
        continue;
      }
      final captureId = _firstListedCapture(
        catalog: catalog,
        entry: entry,
        renderId: render?.id ?? entry.renderId,
        unusableCombinations: unusableCombinations,
        unresolved: skipped,
      );
      if (requireCapture && captureId == null) {
        continue;
      }
      if (!requireCapture &&
          render != null &&
          _isUnusable(
            unusableCombinations,
            renderId: render.id,
            captureId: null,
          )) {
        continue;
      }
      if (requireRender && render == null) {
        continue;
      }
      return PreferenceResolution(
        desired: PairingSnapshot(
          captureId: requireCapture ? captureId : null,
          renderId: requireRender ? render?.id : null,
        ),
        preferenceControlled: true,
        unresolvedIds: skipped,
      );
    }
    if (catalogFallback && !requireCapture) {
      final render = catalog.where((item) => !item.isCapture).where((item) {
        return !_isUnusable(
          unusableCombinations,
          renderId: item.id,
          captureId: null,
        );
      }).firstOrNull;
      if (render != null) {
        return PreferenceResolution(
          desired: PairingSnapshot(renderId: render.id),
          preferenceControlled: true,
          unresolvedIds: skipped,
        );
      }
    }
    if (catalogFallback && !requireRender) {
      final capture = catalog.where((item) => item.isCapture).where((item) {
        return !_isUnusable(
          unusableCombinations,
          renderId: null,
          captureId: item.id,
        );
      }).firstOrNull;
      if (capture != null) {
        return PreferenceResolution(
          desired: PairingSnapshot(captureId: capture.id),
          preferenceControlled: true,
          unresolvedIds: skipped,
        );
      }
    }
    return PreferenceResolution(
      desired: const PairingSnapshot(),
      preferenceControlled: true,
      unresolvedIds: skipped,
      exhausted: true,
    );
  }

  PreferenceResolution? _explicit(
    List<Endpoint> catalog, {
    required List<EndpointPreferenceEntry> entries,
    required bool requireCapture,
    required bool requireRender,
    required String? explicitCaptureId,
    required String? explicitRenderId,
    required Set<UnusableCombination> unusableCombinations,
  }) {
    if (explicitCaptureId == null && explicitRenderId == null) {
      return null;
    }
    final capture = _byId(catalog, explicitCaptureId);
    final render = _byId(catalog, explicitRenderId);
    if (explicitRenderId != null && (render == null || render.isCapture)) {
      return null;
    }
    if (explicitCaptureId != null &&
        explicitRenderId == null &&
        (capture == null || !capture.isCapture)) {
      return null;
    }

    var captureId = (capture != null && capture.isCapture) ? capture.id : null;
    final renderId = render?.id;
    if (render != null && captureId == null) {
      captureId = _autoCapture(
        catalog: catalog,
        entries: entries,
        render: render,
        unusableCombinations: unusableCombinations,
      );
    }
    if (requireCapture && captureId == null && render == null) {
      return null;
    }
    if (requireRender && renderId == null) {
      if (explicitRenderId != null) {
        return null;
      }
      if (requireCapture && captureId != null) {
        return PreferenceResolution(
          desired: PairingSnapshot(captureId: captureId),
          preferenceControlled: false,
        );
      }
      return null;
    }

    final auto = render == null
        ? null
        : _autoCapture(
            catalog: catalog,
            entries: entries,
            render: render,
            unusableCombinations: unusableCombinations,
          );
    final captureOverride =
        explicitCaptureId != null &&
        captureId != null &&
        auto != null &&
        captureId != auto;
    return PreferenceResolution(
      desired: PairingSnapshot(
        captureId: requireCapture ? captureId : null,
        renderId: requireRender ? renderId : null,
        captureOverride: captureOverride,
      ),
      preferenceControlled: false,
    );
  }

  String? _autoCapture({
    required List<Endpoint> catalog,
    required List<EndpointPreferenceEntry> entries,
    required Endpoint render,
    required Set<UnusableCombination> unusableCombinations,
  }) {
    final row = _rowFor(entries, render.id);
    if (row != null) {
      return _firstListedCapture(
        catalog: catalog,
        entry: row,
        renderId: render.id,
        unusableCombinations: unusableCombinations,
      );
    }
    final mate = _pairer.pairFor(render, catalog)?.capture;
    if (mate != null &&
        !_isUnusable(
          unusableCombinations,
          renderId: render.id,
          captureId: mate.id,
        )) {
      return mate.id;
    }
    return _firstCaptureAcrossRows(
      catalog: catalog,
      entries: entries,
      renderId: render.id,
      unusableCombinations: unusableCombinations,
    );
  }

  String? _firstCaptureAcrossRows({
    required List<Endpoint> catalog,
    required List<EndpointPreferenceEntry> entries,
    required String? renderId,
    required Set<UnusableCombination> unusableCombinations,
  }) {
    final seen = <String>{};
    for (final entry in entries) {
      if (!entry.enabled) {
        continue;
      }
      for (final slot in entry.captures) {
        if (!slot.enabled || seen.contains(slot.id)) {
          continue;
        }
        seen.add(slot.id);
        final capture = _byId(catalog, slot.id);
        if (capture == null || !capture.isCapture) {
          continue;
        }
        if (_isUnusable(
          unusableCombinations,
          renderId: renderId,
          captureId: capture.id,
        )) {
          continue;
        }
        return capture.id;
      }
    }
    return catalog.where((item) => item.isCapture).where((item) {
      return !_isUnusable(
        unusableCombinations,
        renderId: renderId,
        captureId: item.id,
      );
    }).firstOrNull?.id;
  }

  String? _firstListedCapture({
    required List<Endpoint> catalog,
    required EndpointPreferenceEntry entry,
    required String? renderId,
    required Set<UnusableCombination> unusableCombinations,
    List<String>? unresolved,
  }) {
    for (final slot in entry.captures) {
      if (!slot.enabled) {
        continue;
      }
      final capture = _byId(catalog, slot.id);
      if (capture == null) {
        unresolved?.add(slot.id);
        continue;
      }
      if (!capture.isCapture) {
        continue;
      }
      if (_isUnusable(
        unusableCombinations,
        renderId: renderId,
        captureId: capture.id,
      )) {
        continue;
      }
      return capture.id;
    }
    return null;
  }

  EndpointPreferenceEntry? _rowFor(
    List<EndpointPreferenceEntry> entries,
    String renderId,
  ) {
    for (final entry in entries) {
      if (entry.enabled && entry.renderId == renderId) {
        return entry;
      }
    }
    return null;
  }

  bool _isUnusable(
    Set<UnusableCombination> unusableCombinations, {
    required String? renderId,
    required String? captureId,
  }) {
    return unusableCombinations.contains(
          UnusableCombination(renderId: renderId, captureId: captureId),
        ) ||
        (renderId != null &&
            unusableCombinations.contains(
              UnusableCombination(renderId: null, captureId: captureId),
            ));
  }

  Endpoint? _byId(List<Endpoint> catalog, String? id) {
    if (id == null) {
      return null;
    }
    return catalog.where((endpoint) => endpoint.id == id).firstOrNull;
  }
}
