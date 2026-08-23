import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
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
    Endpoint(
      id: 'car-in',
      name: 'Car',
      routeClass: RouteClass.car,
      isCapture: true,
      pairId: 'car',
    ),
    Endpoint(
      id: 'car-out',
      name: 'Car',
      routeClass: RouteClass.car,
      isCapture: false,
      pairId: 'car',
    ),
  ];

  const resolver = PreferenceResolver();

  test(
    'platform default prefers bluetooth, then car, speakerphone, handset',
    () {
      final preference = EndpointPreference.platformDefault(catalog);
      expect(preference.entries.map((e) => e.id), [
        'airpods-in',
        'car-in',
        'speaker-in',
        'handset-in',
      ]);
    },
  );

  test('empty preference resolves the first complete default Pair', () {
    final resolved = resolver.resolve(catalog: catalog);
    expect(resolved.desired.captureId, 'airpods-in');
    expect(resolved.desired.renderId, 'airpods-out');
    expect(resolved.preferenceControlled, isTrue);
  });

  test('walks enabled preference and skips unavailable retained ids', () {
    const preference = EndpointPreference(
      entries: [
        EndpointPreferenceEntry(id: 'missing-bt'),
        EndpointPreferenceEntry(id: 'speaker-in'),
        EndpointPreferenceEntry(id: 'handset-in'),
      ],
    );
    final resolved = resolver.resolve(catalog: catalog, preference: preference);
    expect(resolved.desired.captureId, 'speaker-in');
    expect(resolved.unresolvedIds, ['missing-bt']);
  });

  test('disabled Endpoints are skipped by automatic resolution', () {
    const preference = EndpointPreference(
      entries: [
        EndpointPreferenceEntry(id: 'airpods-in', enabled: false),
        EndpointPreferenceEntry(id: 'speaker-in'),
      ],
    );
    final resolved = resolver.resolve(catalog: catalog, preference: preference);
    expect(resolved.desired.captureId, 'speaker-in');
  });

  test('explicit selection wins while the Endpoint remains available', () {
    final resolved = resolver.resolve(
      catalog: catalog,
      explicitCaptureId: 'handset-in',
    );
    expect(resolved.desired.captureId, 'handset-in');
    expect(resolved.desired.renderId, 'handset-out');
    expect(resolved.preferenceControlled, isFalse);
  });

  test(
    'explicit split capture/render is kept and not completed from preference',
    () {
      final resolved = resolver.resolve(
        catalog: catalog,
        explicitCaptureId: 'airpods-in',
        explicitRenderId: 'speaker-out',
      );
      expect(resolved.desired.captureId, 'airpods-in');
      expect(resolved.desired.renderId, 'speaker-out');
      expect(resolved.desired.renderOverride, isTrue);
      expect(resolved.preferenceControlled, isFalse);
    },
  );

  test('disappeared explicit selection expires back to preference', () {
    const withoutAirPods = [
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
    ];
    final resolved = resolver.resolve(
      catalog: withoutAirPods,
      explicitCaptureId: 'airpods-in',
    );
    expect(resolved.preferenceControlled, isTrue);
    expect(resolved.desired.captureId, 'speaker-in');
  });

  test('incomplete automatic Pairs are skipped', () {
    const captureOnlyBluetooth = [
      Endpoint(
        id: 'bt-in',
        name: 'BT',
        routeClass: RouteClass.bluetooth,
        isCapture: true,
        pairId: 'bt',
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
    ];
    final resolved = resolver.resolve(catalog: captureOnlyBluetooth);
    expect(resolved.desired.captureId, 'speaker-in');
    expect(resolved.desired.renderId, 'speaker-out');
  });

  test('unusable preference Pairs walk downward until exhaustion', () {
    final resolved = resolver.resolve(
      catalog: catalog,
      unusablePairIds: {'airpods', 'car', 'Speakerphone', 'Handset'},
    );
    expect(resolved.exhausted, isTrue);
    expect(resolved.desired.captureId, isNull);
  });

  test('playback-only may resolve a render-only Pair', () {
    const renderOnly = [
      Endpoint(
        id: 'speaker-out',
        name: 'Speakerphone',
        routeClass: RouteClass.speakerphone,
        isCapture: false,
      ),
    ];
    final resolved = resolver.resolve(
      catalog: renderOnly,
      requireCapture: false,
    );
    expect(resolved.desired.renderId, 'speaker-out');
    expect(resolved.exhausted, isFalse);
  });
}
