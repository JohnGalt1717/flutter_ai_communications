import 'package:flutter/foundation.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_orchestration_support.dart';

/// Desktop host preference: webcam capture + USB render first, AirPods below.
void main() {
  installNativeOrchestrationLogging();

  testWidgets(
    'native Orchestration: BRIO capture and USB render outrank AirPods',
    (tester) async {
      final platform = FlutterAiCommunicationsPlatform.instance;
      expect(
        platform.runtimeType.toString(),
        isNot(contains('Loopback')),
        reason: 'native suite must not wrap the registered adapter',
      );

      final manager = CommunicationsManager();
      addTearDown(() async {
        await manager.session?.stop();
      });

      var catalog = await manager.endpoints();
      if (catalog.isEmpty) {
        final primed = await requireReady(manager, purpose: 'desktop-catalog');
        catalog = await manager.endpoints();
        await primed.stop();
      }
      expect(catalog, isNotEmpty);

      final brio = catalog
          .where(
            (endpoint) =>
                endpoint.isCapture &&
                endpoint.name.toLowerCase().contains('brio'),
          )
          .firstOrNull;
      final usbRenders = catalog.where(
        (endpoint) =>
            !endpoint.isCapture && endpoint.name.toLowerCase().contains('usb'),
      );
      final usbRender =
          usbRenders
              .where(
                (endpoint) => endpoint.name.toLowerCase().startsWith('usb'),
              )
              .firstOrNull ??
          usbRenders.firstOrNull;
      final airpods = completePair(catalog, RouteClass.bluetooth);
      expect(brio, isNotNull, reason: 'Logitech BRIO capture must be present');
      expect(
        usbRender,
        isNotNull,
        reason: 'USB render Endpoint must be present',
      );
      expect(
        airpods?.capture,
        isNotNull,
        reason: 'AirPods must stay connected so the OS can try to force them',
      );
      expect(
        airpods?.render,
        isNotNull,
        reason: 'AirPods render Endpoint must be present',
      );
      final capture = brio!;
      final speakers = usbRender!;
      final pair = airpods!;

      nativeOrchestrationLog.info('NATIVE_CATALOG ${catalogSummary(catalog)}');
      nativeOrchestrationLog.info(
        'DESKTOP_PREFERENCE capture=${capture.id} render=${speakers.id} '
        'airpodsBelow=${pair.capture!.id}',
      );

      final session = await requireReady(
        manager,
        purpose: 'desktop-brio-usb-over-airpods',
        preference: SessionPreference(
          soundFloor: 0,
          endpoints: EndpointPreference(
            entries: [
              EndpointPreferenceEntry(
                renderId: speakers.id,
                captures: [EndpointPreferenceCapture(id: capture.id)],
              ),
              EndpointPreferenceEntry(
                renderId: pair.render!.id,
                captures: [EndpointPreferenceCapture(id: pair.capture!.id)],
              ),
            ],
          ),
        ),
      );

      expect(
        session.diagnostics.preferenceControlled,
        isTrue,
        reason: 'this is host Endpoint preference, not Explicit selection',
      );
      expect(session.diagnostics.desired.captureId, capture.id);
      expect(session.diagnostics.desired.renderId, speakers.id);
      expect(session.diagnostics.desired.captureId, isNot(pair.capture!.id));
      expect(session.diagnostics.desired.renderId, isNot(pair.render?.id));
      await assertObserved(session);
      expect(session.diagnostics.observed.captureId, capture.id);
      expect(session.diagnostics.observed.renderId, speakers.id);
      expect(session.diagnostics.observed.captureId, isNot(pair.capture!.id));

      await writeReceipt({
        'commit': hostCommit(),
        'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
        'os': hostOs(),
        'osVersion': hostOsVersion(),
        'hardware': hostHardware(),
        'permission': 'granted',
        'catalog': [
          for (final endpoint in catalog)
            {
              'id': endpoint.id,
              'name': endpoint.name,
              'routeClass': endpoint.routeClass.name,
              'isCapture': endpoint.isCapture,
              'pairId': endpoint.pairId,
            },
        ],
        'preference': {
          'capture': capture.id,
          'render': speakers.id,
          'airpods': pair.capture!.id,
        },
        'session': snapshot(session, caseName: 'brio-usb-over-airpods'),
        'nativeFailuresSkipped': false,
      });
      await session.stop();
      expect(manager.session, isNull);
    },
  );

  testWidgets(
    'native Orchestration: explicit USB render auto-completes Brio from the row',
    (tester) async {
      final platform = FlutterAiCommunicationsPlatform.instance;
      expect(
        platform.runtimeType.toString(),
        isNot(contains('Loopback')),
        reason: 'native suite must not wrap the registered adapter',
      );

      final manager = CommunicationsManager();
      addTearDown(() async {
        await manager.session?.stop();
      });

      var catalog = await manager.endpoints();
      if (catalog.isEmpty) {
        final primed = await requireReady(manager, purpose: 'desktop-catalog');
        catalog = await manager.endpoints();
        await primed.stop();
      }

      final brio = catalog
          .where(
            (endpoint) =>
                endpoint.isCapture &&
                endpoint.name.toLowerCase().contains('brio'),
          )
          .firstOrNull;
      final usbRender = catalog
          .where(
            (endpoint) =>
                !endpoint.isCapture &&
                endpoint.name.toLowerCase().contains('usb'),
          )
          .firstOrNull;
      final airpods = completePair(catalog, RouteClass.bluetooth);
      expect(brio, isNotNull);
      expect(usbRender, isNotNull);
      expect(airpods?.capture, isNotNull);
      expect(airpods?.render, isNotNull);
      final capture = brio!;
      final speakers = usbRender!;
      final pair = airpods!;

      final session = await requireReady(
        manager,
        purpose: 'desktop-explicit-usb-completes-brio',
        preference: SessionPreference(
          soundFloor: 0,
          endpoints: EndpointPreference(
            entries: [
              EndpointPreferenceEntry(
                renderId: pair.render!.id,
                captures: [EndpointPreferenceCapture(id: pair.capture!.id)],
              ),
              EndpointPreferenceEntry(
                renderId: speakers.id,
                captures: [
                  EndpointPreferenceCapture(id: capture.id),
                  EndpointPreferenceCapture(id: pair.capture!.id),
                ],
              ),
            ],
          ),
        ),
      );
      expect(session.diagnostics.desired.renderId, pair.render!.id);
      await session.select(renderId: speakers.id);
      expect(session.diagnostics.preferenceControlled, isFalse);
      expect(session.diagnostics.desired.renderId, speakers.id);
      expect(session.diagnostics.desired.captureId, capture.id);
      expect(session.preference.endpoints.entries, isNotEmpty);
      await assertObserved(session);
      await writeReceipt({
        'commit': hostCommit(),
        'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
        'os': hostOs(),
        'osVersion': hostOsVersion(),
        'hardware': hostHardware(),
        'permission': 'granted',
        'preference': {
          'explicitRender': speakers.id,
          'autoCapture': capture.id,
        },
        'session': snapshot(session, caseName: 'explicit-usb-completes-brio'),
        'nativeFailuresSkipped': false,
      });
      await session.stop();
      expect(manager.session, isNull);
    },
  );
}
