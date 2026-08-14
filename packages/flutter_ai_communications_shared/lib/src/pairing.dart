import 'endpoint.dart';

/// Resolved capture/render ids and whether a side is an ephemeral override.
final class PairingSnapshot {
  /// Creates a pairing snapshot.
  const PairingSnapshot({
    this.captureId,
    this.renderId,
    this.renderOverride = false,
    this.captureOverride = false,
  });

  /// Selected capture Endpoint id.
  final String? captureId;

  /// Selected render Endpoint id.
  final String? renderId;

  /// Render was chosen independently of the capture Pair.
  final bool renderOverride;

  /// Capture was chosen independently of the render Pair.
  final bool captureOverride;

  @override
  bool operator ==(Object other) =>
      other is PairingSnapshot &&
      other.captureId == captureId &&
      other.renderId == renderId &&
      other.renderOverride == renderOverride &&
      other.captureOverride == captureOverride;

  @override
  int get hashCode =>
      Object.hash(captureId, renderId, renderOverride, captureOverride);
}

/// Pairs capture and render by hardware identity.
///
/// Selecting one side of a Pair selects the other unless that side has an
/// ephemeral override. A disappearing override clears. A disappearing Pair
/// falls back to speakerphone. OS-forced routes apply and clear overrides.
final class EndpointPairer {
  /// Creates a pairer.
  const EndpointPairer();

  /// Pair for [endpoint] in [catalog], if the other side exists.
  Pair? pairFor(Endpoint endpoint, List<Endpoint> catalog) {
    final capture = endpoint.isCapture
        ? endpoint
        : catalog
              .where((e) => e.pairId == endpoint.pairId && e.isCapture)
              .firstOrNull;
    final render = !endpoint.isCapture
        ? endpoint
        : catalog
              .where((e) => e.pairId == endpoint.pairId && !e.isCapture)
              .firstOrNull;
    if (capture == null && render == null) {
      return null;
    }
    return Pair(id: endpoint.pairId, capture: capture, render: render);
  }

  /// Speakerphone Endpoints in [catalog].
  Pair? speakerphone(List<Endpoint> catalog) {
    final capture = catalog
        .where((e) => e.routeClass == RouteClass.speakerphone && e.isCapture)
        .firstOrNull;
    final render = catalog
        .where((e) => e.routeClass == RouteClass.speakerphone && !e.isCapture)
        .firstOrNull;
    if (capture == null && render == null) {
      return null;
    }
    return Pair(
      id: capture?.pairId ?? render!.pairId,
      capture: capture,
      render: render,
    );
  }

  /// Apply an ephemeral select. Does not persist host preference.
  PairingSnapshot select(
    PairingSnapshot state,
    List<Endpoint> catalog, {
    String? captureId,
    String? renderId,
  }) {
    var next = state;
    if (captureId != null) {
      next = _selectCapture(next, catalog, captureId);
    }
    if (renderId != null) {
      next = _selectRender(next, catalog, renderId);
    }
    return next;
  }

  /// Re-resolve after the catalog changes.
  PairingSnapshot onCatalogChanged(
    PairingSnapshot state,
    List<Endpoint> catalog,
  ) {
    final captureExists = _byId(catalog, state.captureId) != null;
    final renderExists = _byId(catalog, state.renderId) != null;
    if (!captureExists) {
      return _fromPair(speakerphone(catalog));
    }
    if (!renderExists) {
      final capture = _byId(catalog, state.captureId);
      final mate = capture == null ? null : _mate(catalog, capture);
      return PairingSnapshot(
        captureId: state.captureId,
        renderId: mate?.id,
      );
    }
    if (state.renderOverride && !renderExists) {
      return select(state, catalog, captureId: state.captureId);
    }
    return state;
  }

  /// OS-forced route is truth; overrides clear.
  PairingSnapshot onOsForced(
    List<Endpoint> catalog, {
    String? captureId,
    String? renderId,
  }) {
    String? cap = captureId;
    String? ren = renderId;
    if (cap != null && ren == null) {
      final capture = _byId(catalog, cap);
      ren = capture == null ? null : _mate(catalog, capture)?.id;
    }
    if (ren != null && cap == null) {
      final render = _byId(catalog, ren);
      cap = render == null ? null : _mate(catalog, render)?.id;
    }
    return PairingSnapshot(captureId: cap, renderId: ren);
  }

  PairingSnapshot _selectCapture(
    PairingSnapshot state,
    List<Endpoint> catalog,
    String captureId,
  ) {
    final capture = _byId(catalog, captureId);
    if (capture == null) {
      return state;
    }
    final mate = _mate(catalog, capture);
    final keepRender =
        state.renderOverride && _byId(catalog, state.renderId) != null;
    return PairingSnapshot(
      captureId: capture.id,
      renderId: keepRender ? state.renderId : mate?.id ?? state.renderId,
      renderOverride: keepRender,
    );
  }

  PairingSnapshot _selectRender(
    PairingSnapshot state,
    List<Endpoint> catalog,
    String renderId,
  ) {
    final render = _byId(catalog, renderId);
    if (render == null) {
      return state;
    }
    final mate = _mate(catalog, render);
    final followsCapture = mate != null && mate.id == state.captureId;
    if (followsCapture || state.captureId == null) {
      return PairingSnapshot(
        captureId: state.captureId ?? mate?.id,
        renderId: render.id,
      );
    }
    return PairingSnapshot(
      captureId: state.captureId,
      renderId: render.id,
      renderOverride: true,
      captureOverride: state.captureOverride,
    );
  }

  PairingSnapshot _fromPair(Pair? pair) => PairingSnapshot(
    captureId: pair?.capture?.id,
    renderId: pair?.render?.id,
  );

  Endpoint? _byId(List<Endpoint> catalog, String? id) {
    if (id == null) {
      return null;
    }
    return catalog.where((e) => e.id == id).firstOrNull;
  }

  Endpoint? _mate(List<Endpoint> catalog, Endpoint endpoint) => catalog
      .where((e) => e.pairId == endpoint.pairId && e.isCapture != endpoint.isCapture)
      .firstOrNull;
}
