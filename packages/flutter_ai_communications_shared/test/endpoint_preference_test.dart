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

  const brio = Endpoint(
    id: 'brio-in',
    name: 'Logitech BRIO',
    routeClass: RouteClass.wired,
    isCapture: true,
    pairId: 'logitech brio',
  );
  const usbOut = Endpoint(
    id: 'usb-out',
    name: 'USB Audio',
    routeClass: RouteClass.wired,
    isCapture: false,
    pairId: 'usb audio',
  );

  const resolver = PreferenceResolver();

  EndpointPreferenceEntry row(
    String renderId,
    List<String> captureIds, {
    bool enabled = true,
  }) {
    return EndpointPreferenceEntry(
      renderId: renderId,
      enabled: enabled,
      captures: [
        for (final id in captureIds) EndpointPreferenceCapture(id: id),
      ],
    );
  }

  test(
    'platform default prefers bluetooth, then car, speakerphone, handset',
    () {
      final preference = EndpointPreference.platformDefault(catalog);
      expect(preference.entries.map((e) => e.renderId), [
        'airpods-out',
        'car-out',
        'speaker-out',
        'handset-out',
      ]);
      expect(preference.entries.first.captures.single.id, 'airpods-in');
    },
  );

  test('empty preference resolves the first complete default Pair', () {
    final resolved = resolver.resolve(catalog: catalog);
    expect(resolved.desired.captureId, 'airpods-in');
    expect(resolved.desired.renderId, 'airpods-out');
    expect(resolved.preferenceControlled, isTrue);
    expect(resolved.desired.captureOverride, isFalse);
    expect(resolved.desired.renderOverride, isFalse);
  });

  test('walks enabled preference and skips unavailable retained ids', () {
    final preference = EndpointPreference(
      entries: [
        row('missing-bt', ['missing-bt-in']),
        row('speaker-out', ['speaker-in']),
        row('handset-out', ['handset-in']),
      ],
    );
    final resolved = resolver.resolve(catalog: catalog, preference: preference);
    expect(resolved.desired.captureId, 'speaker-in');
    expect(resolved.desired.renderId, 'speaker-out');
    expect(resolved.unresolvedIds, contains('missing-bt'));
  });

  test('disabled render rows are skipped by automatic resolution', () {
    final preference = EndpointPreference(
      entries: [
        row('airpods-out', ['airpods-in'], enabled: false),
        row('speaker-out', ['speaker-in']),
      ],
    );
    final resolved = resolver.resolve(catalog: catalog, preference: preference);
    expect(resolved.desired.captureId, 'speaker-in');
    expect(resolved.desired.renderId, 'speaker-out');
  });

  test('disabled capture slots are skipped on the same render row', () {
    final preference = EndpointPreference(
      entries: [
        EndpointPreferenceEntry(
          renderId: 'usb-out',
          captures: const [
            EndpointPreferenceCapture(id: 'brio-in', enabled: false),
            EndpointPreferenceCapture(id: 'airpods-in'),
          ],
        ),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, brio, usbOut],
      preference: preference,
    );
    expect(resolved.desired.renderId, 'usb-out');
    expect(resolved.desired.captureId, 'airpods-in');
  });

  test('explicit render completes capture from the hardware Pair', () {
    final resolved = resolver.resolve(
      catalog: catalog,
      explicitRenderId: 'handset-out',
    );
    expect(resolved.desired.captureId, 'handset-in');
    expect(resolved.desired.renderId, 'handset-out');
    expect(resolved.preferenceControlled, isFalse);
    expect(resolved.desired.captureOverride, isFalse);
  });

  test('explicit capture alone keeps no invented render', () {
    final resolved = resolver.resolve(
      catalog: catalog,
      explicitCaptureId: 'handset-in',
    );
    expect(resolved.desired.captureId, 'handset-in');
    expect(resolved.desired.renderId, isNull);
    expect(resolved.preferenceControlled, isFalse);
  });

  test(
    'explicit split capture/render is kept and flags only a departed capture',
    () {
      final resolved = resolver.resolve(
        catalog: catalog,
        explicitCaptureId: 'airpods-in',
        explicitRenderId: 'speaker-out',
      );
      expect(resolved.desired.captureId, 'airpods-in');
      expect(resolved.desired.renderId, 'speaker-out');
      expect(resolved.desired.captureOverride, isTrue);
      expect(resolved.desired.renderOverride, isFalse);
      expect(resolved.preferenceControlled, isFalse);
    },
  );

  test('disappeared explicit render expires back to preference', () {
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
      explicitRenderId: 'airpods-out',
    );
    expect(resolved.preferenceControlled, isTrue);
    expect(resolved.desired.captureId, 'speaker-in');
    expect(resolved.desired.renderId, 'speaker-out');
  });

  test('host list ranks USB render with Brio capture above AirPods', () {
    final desktop = [brio, usbOut, ...catalog];
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final resolved = resolver.resolve(catalog: desktop, preference: preference);
    expect(resolved.preferenceControlled, isTrue);
    expect(resolved.desired.captureId, 'brio-in');
    expect(resolved.desired.renderId, 'usb-out');
    expect(resolved.desired.captureOverride, isFalse);
    expect(resolved.desired.renderOverride, isFalse);
  });

  test('capture list falls back on the same render when Brio is gone', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in', 'airpods-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, usbOut],
      preference: preference,
    );
    expect(resolved.desired.renderId, 'usb-out');
    expect(resolved.desired.captureId, 'airpods-in');
  });

  test('explicit render does not steal capture from another row', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, usbOut],
      preference: preference,
      explicitRenderId: 'usb-out',
    );
    expect(resolved.preferenceControlled, isFalse);
    expect(resolved.desired.renderId, 'usb-out');
    expect(resolved.desired.captureId, isNull);
  });

  test(
    'unlisted unpaired render walks capture lists when it has no hardware mate',
    () {
      final preference = EndpointPreference(
        entries: [
          row('airpods-out', ['airpods-in', 'brio-in']),
        ],
      );
      final resolved = resolver.resolve(
        catalog: [...catalog, brio, usbOut],
        preference: preference,
        explicitRenderId: 'usb-out',
      );
      expect(resolved.preferenceControlled, isFalse);
      expect(resolved.desired.renderId, 'usb-out');
      expect(resolved.desired.captureId, 'airpods-in');
    },
  );

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

  test('unusable combinations walk downward until exhaustion', () {
    final resolved = resolver.resolve(
      catalog: catalog,
      unusableCombinations: {
        const UnusableCombination(
          renderId: 'airpods-out',
          captureId: 'airpods-in',
        ),
        const UnusableCombination(renderId: 'car-out', captureId: 'car-in'),
        const UnusableCombination(
          renderId: 'speaker-out',
          captureId: 'speaker-in',
        ),
        const UnusableCombination(
          renderId: 'handset-out',
          captureId: 'handset-in',
        ),
      },
    );
    expect(resolved.exhausted, isTrue);
    expect(resolved.desired.captureId, isNull);
  });

  test('unusable combination tries the next capture on the same row', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in', 'airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, brio, usbOut],
      preference: preference,
      unusableCombinations: {
        const UnusableCombination(renderId: 'usb-out', captureId: 'brio-in'),
      },
    );
    expect(resolved.desired.renderId, 'usb-out');
    expect(resolved.desired.captureId, 'airpods-in');
  });

  test('capture-only walks capture lists without requiring the render', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, brio],
      preference: preference,
      requireRender: false,
    );
    expect(resolved.desired.captureId, 'brio-in');
    expect(resolved.desired.renderId, isNull);
  });

  test('capture-only does not fill unused render', () {
    final resolved = resolver.resolve(catalog: catalog, requireRender: false);
    expect(resolved.desired.captureId, isNotNull);
    expect(resolved.desired.renderId, isNull);
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

  test('same capture Endpoint may appear on many render rows', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
        row('speaker-out', ['brio-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final desktop = [...catalog, brio, usbOut];
    expect(
      resolver
          .resolve(catalog: desktop, preference: preference)
          .desired
          .renderId,
      'usb-out',
    );
    expect(
      resolver
          .resolve(
            catalog: desktop.where((e) => e.id != 'usb-out').toList(),
            preference: preference,
          )
          .desired
          .renderId,
      'speaker-out',
    );
    expect(
      resolver
          .resolve(
            catalog: desktop.where((e) => e.id != 'usb-out').toList(),
            preference: preference,
          )
          .desired
          .captureId,
      'brio-in',
    );
  });

  test('preference walk skips a row whose listed captures are all gone', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, usbOut],
      preference: preference,
    );
    expect(resolved.desired.renderId, 'airpods-out');
    expect(resolved.desired.captureId, 'airpods-in');
  });

  test('empty capture list is skipped on the preference walk', () {
    final preference = EndpointPreference(
      entries: [
        const EndpointPreferenceEntry(renderId: 'usb-out'),
        row('speaker-out', ['speaker-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, usbOut],
      preference: preference,
    );
    expect(resolved.desired.renderId, 'speaker-out');
  });

  test('explicit render uses the row capture list, not the hardware mate', () {
    final preference = EndpointPreference(
      entries: [
        row('airpods-out', ['brio-in', 'airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, brio],
      preference: preference,
      explicitRenderId: 'airpods-out',
    );
    expect(resolved.desired.renderId, 'airpods-out');
    expect(resolved.desired.captureId, 'brio-in');
    expect(resolved.desired.captureOverride, isFalse);
    expect(resolved.preferenceControlled, isFalse);
  });

  test('explicit both matching auto is not a capture override', () {
    final resolved = resolver.resolve(
      catalog: catalog,
      explicitCaptureId: 'handset-in',
      explicitRenderId: 'handset-out',
    );
    expect(resolved.desired.captureOverride, isFalse);
    expect(resolved.preferenceControlled, isFalse);
  });

  test(
    'unlisted unpaired render with empty preference walks default captures',
    () {
      final resolved = resolver.resolve(
        catalog: [...catalog, brio, usbOut],
        explicitRenderId: 'usb-out',
      );
      expect(resolved.preferenceControlled, isFalse);
      expect(resolved.desired.renderId, 'usb-out');
      expect(resolved.desired.captureId, 'airpods-in');
    },
  );

  test('bound playback-only list does not guess an unlisted render', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: catalog,
      preference: preference,
      requireCapture: false,
    );
    expect(resolved.exhausted, isTrue);
    expect(resolved.desired.renderId, isNull);
  });

  test('playback-only walks render rows and ignores capture lists', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, usbOut],
      preference: preference,
      requireCapture: false,
    );
    expect(resolved.desired.renderId, 'usb-out');
    expect(resolved.desired.captureId, isNull);
  });

  test('unusable first row walks to the next render row', () {
    final preference = EndpointPreference(
      entries: [
        row('usb-out', ['brio-in']),
        row('airpods-out', ['airpods-in']),
      ],
    );
    final resolved = resolver.resolve(
      catalog: [...catalog, brio, usbOut],
      preference: preference,
      unusableCombinations: {
        const UnusableCombination(renderId: 'usb-out', captureId: 'brio-in'),
      },
    );
    expect(resolved.desired.renderId, 'airpods-out');
    expect(resolved.desired.captureId, 'airpods-in');
  });

  test(
    'EndpointCatalogGroups splits complete Pairs from unpaired Endpoints',
    () {
      final groups = EndpointCatalogGroups.of([...catalog, brio, usbOut]);
      expect(groups.completePairs.map((p) => p.id), contains('airpods'));
      expect(groups.unpairedRenders.map((e) => e.id), ['usb-out']);
      expect(groups.unpairedCaptures.map((e) => e.id), ['brio-in']);
    },
  );
}
