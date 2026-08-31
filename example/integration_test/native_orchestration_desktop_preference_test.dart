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

      nativeOrchestrationLog.info('NATIVE_CATALOG ${catalogSummary(catalog)}');
      nativeOrchestrationLog.info(
        'DESKTOP_PREFERENCE capture=${brio!.id} render=${usbRender!.id} '
        'airpodsBelow=${airpods!.capture!.id}',
      );

      final session = await requireReady(
        manager,
        purpose: 'desktop-brio-usb-over-airpods',
        preference: SessionPreference(
          soundFloor: 0,
          endpoints: EndpointPreference(
            entries: [
              EndpointPreferenceEntry(id: brio.id),
              EndpointPreferenceEntry(id: usbRender.id),
              EndpointPreferenceEntry(id: airpods.capture!.id),
            ],
          ),
        ),
      );

      expect(
        session.diagnostics.preferenceControlled,
        isTrue,
        reason: 'this is host Endpoint preference, not Explicit selection',
      );
      expect(session.diagnostics.desired.captureId, brio.id);
      expect(session.diagnostics.desired.renderId, usbRender.id);
      expect(session.diagnostics.desired.captureId, isNot(airpods.capture!.id));
      expect(session.diagnostics.desired.renderId, isNot(airpods.render?.id));
      await assertObserved(session);
      expect(session.diagnostics.observed.captureId, brio.id);
      expect(session.diagnostics.observed.renderId, usbRender.id);
      expect(
        session.diagnostics.observed.captureId,
        isNot(airpods.capture!.id),
      );

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
          'capture': brio.id,
          'render': usbRender.id,
          'airpods': airpods.capture!.id,
        },
        'session': snapshot(session, caseName: 'brio-usb-over-airpods'),
        'nativeFailuresSkipped': false,
      });
      await session.stop();
      expect(manager.session, isNull);
    },
  );
}
