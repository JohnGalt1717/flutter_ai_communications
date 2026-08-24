import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  const pairer = EndpointPairer();
  const catalog = [
    Endpoint(
      id: 'handset-in',
      name: 'Handset',
      routeClass: RouteClass.handset,
      isCapture: true,
    ),
    Endpoint(
      id: 'handset-out',
      name: 'Handset',
      routeClass: RouteClass.handset,
      isCapture: false,
    ),
    Endpoint(
      id: 'speaker-in',
      name: 'Speakerphone',
      routeClass: RouteClass.speakerphone,
      isCapture: true,
    ),
    Endpoint(
      id: 'speaker-out',
      name: 'Speakerphone',
      routeClass: RouteClass.speakerphone,
      isCapture: false,
    ),
    Endpoint(
      id: 'airpods-in',
      name: 'AirPods',
      routeClass: RouteClass.bluetooth,
      isCapture: true,
      pairId: 'airpods',
    ),
    Endpoint(
      id: 'airpods-out',
      name: 'AirPods',
      routeClass: RouteClass.bluetooth,
      isCapture: false,
      pairId: 'airpods',
    ),
  ];

  test('handset and speakerphone are distinct selectable Endpoints', () {
    expect(
      catalog.where((e) => e.routeClass == RouteClass.handset),
      hasLength(2),
    );
    expect(
      catalog.where((e) => e.routeClass == RouteClass.speakerphone),
      hasLength(2),
    );
  });

  test('AirPods-in follows render', () {
    const idle = PairingSnapshot();
    final next = pairer.select(idle, catalog, captureId: 'airpods-in');
    expect(next.captureId, 'airpods-in');
    expect(next.renderId, 'airpods-out');
    expect(next.renderOverride, isFalse);
  });

  test(
    'render override stays split until the override Endpoint disappears',
    () {
      var state = pairer.select(
        const PairingSnapshot(),
        catalog,
        captureId: 'airpods-in',
      );
      state = pairer.select(state, catalog, renderId: 'speaker-out');
      expect(state.captureId, 'airpods-in');
      expect(state.renderId, 'speaker-out');
      expect(state.renderOverride, isTrue);

      state = pairer.select(state, catalog, captureId: 'airpods-in');
      expect(state.renderId, 'speaker-out');
      expect(state.renderOverride, isTrue);
    },
  );

  test('AirPods-out falls back to speakerphone', () {
    var state = pairer.select(
      const PairingSnapshot(),
      catalog,
      captureId: 'airpods-in',
    );
    final withoutAirPods = catalog.where((e) => e.pairId != 'airpods').toList();
    state = pairer.onCatalogChanged(state, withoutAirPods);
    expect(state.captureId, 'speaker-in');
    expect(state.renderId, 'speaker-out');
    expect(state.renderOverride, isFalse);
  });

  test('OS-forced re-pair applies and clears override', () {
    var state = pairer.select(
      const PairingSnapshot(),
      catalog,
      captureId: 'airpods-in',
      renderId: 'speaker-out',
    );
    expect(state.renderOverride, isTrue);
    state = pairer.onOsForced(catalog, captureId: 'airpods-in');
    expect(state.captureId, 'airpods-in');
    expect(state.renderId, 'airpods-out');
    expect(state.renderOverride, isFalse);
  });

  test('pairer does not store a device-order preference list', () {
    expect(pairer.speakerphone(catalog)?.render?.id, 'speaker-out');
    expect(
      pairer.select(const PairingSnapshot(), catalog, captureId: 'handset-in'),
      const PairingSnapshot(captureId: 'handset-in', renderId: 'handset-out'),
    );
  });
}
