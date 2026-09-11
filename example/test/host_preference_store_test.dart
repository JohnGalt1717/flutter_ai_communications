import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/host_preference_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = [
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
      id: 'brio-in',
      name: 'Logitech BRIO',
      routeClass: RouteClass.wired,
      isCapture: true,
      pairId: 'logitech brio',
    ),
  ];

  test('camera preference is a separate list from Endpoint preference', () {
    final store = HostPreferenceStore();
    store.preferEndpoint(catalog[0], catalog);
    store.preferCamera('back');

    expect(store.endpoints.entries.single.renderId, 'speaker-out');
    expect(store.endpoints.entries.single.captures.single.id, 'speaker-in');
    expect(store.cameras.entries.single.id, 'back');
  });

  test('preferCamera promotes an id to the front and keeps earlier ids', () {
    final store = HostPreferenceStore();
    store.preferCamera('front');
    store.preferCamera('back');
    store.preferCamera('front');

    expect(store.cameras.entries.map((entry) => entry.id), ['front', 'back']);
  });

  test('preferEndpoint promotes a complete Pair as a render row', () {
    final store = HostPreferenceStore();
    store.preferEndpoint(catalog[2], catalog);
    store.preferEndpoint(catalog[0], catalog);

    expect(store.endpoints.entries.map((entry) => entry.renderId), [
      'speaker-out',
      'airpods-out',
    ]);
    expect(store.endpoints.entries.first.captures.single.id, 'speaker-in');
  });

  test('unpaired capture is not a persisted row', () {
    final store = HostPreferenceStore();
    store.preferEndpoint(catalog[4], catalog);
    expect(store.endpoints.isEmpty, isTrue);
  });

  test('saveEndpoints round-trips rows through the same storage map', () {
    final storage = <String, String>{};
    final first = HostPreferenceStore(storage: storage);
    first.saveEndpoints(
      const EndpointPreference(
        entries: [
          EndpointPreferenceEntry(
            renderId: 'usb-out',
            captures: [EndpointPreferenceCapture(id: 'brio-in')],
          ),
        ],
      ),
    );
    first.preferCamera('back');

    final second = HostPreferenceStore(storage: storage);
    expect(second.endpoints.entries.single.renderId, 'usb-out');
    expect(second.endpoints.entries.single.captures.single.id, 'brio-in');
    expect(second.cameras.entries.single.id, 'back');
  });

  test('preferEndpoint re-enables a disabled row', () {
    final store = HostPreferenceStore();
    store.saveEndpoints(
      const EndpointPreference(
        entries: [
          EndpointPreferenceEntry(
            renderId: 'speaker-out',
            enabled: false,
            captures: [EndpointPreferenceCapture(id: 'speaker-in')],
          ),
        ],
      ),
    );
    store.preferEndpoint(catalog[0], catalog);
    expect(store.endpoints.entries.single.enabled, isTrue);
  });

  test('persist callback is invoked for camera writes', () async {
    final writes = <String, String>{};
    final store = HostPreferenceStore(
      persist: (key, value) async {
        writes[key] = value;
      },
    );
    store.preferCamera('back');
    await Future<void>.delayed(Duration.zero);
    expect(writes[HostPreferenceStore.camerasKey], contains('back'));
  });

  test('corrupt stored JSON is an empty preference, not a crash', () {
    final store = HostPreferenceStore(
      storage: {
        HostPreferenceStore.endpointsKey: '{not-json',
        HostPreferenceStore.camerasKey: '[]',
      },
    );

    expect(store.endpoints.isEmpty, isTrue);
    expect(store.cameras.isEmpty, isTrue);
  });
}
