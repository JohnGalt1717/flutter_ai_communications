import 'package:flutter/foundation.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_marionette_support.dart';

/// Native Session proof. Never wraps the platform in loopback.
void main() {
  installNativeMarionetteLogging();

  testWidgets('native Marionette: start, route, twenty cycles', (tester) async {
    final platform = FlutterAiCommunicationsPlatform.instance;
    expect(
      platform.runtimeType.toString(),
      isNot(contains('Loopback')),
      reason: 'native suite must not wrap the registered adapter',
    );

    final manager = AudioManager();
    addTearDown(() async {
      await manager.session?.stop();
    });

    var catalog = await manager.endpoints();
    Session? first;
    if (catalog.isEmpty) {
      first = await requireReady(manager, purpose: 'native-first');
      catalog = await manager.endpoints();
    }
    expect(catalog, isNotEmpty, reason: 'native catalog must be non-empty');
    first ??= await requireReady(manager, purpose: 'native-first');
    final firstCapture = first.capture;
    nativeMarionetteLog.info('NATIVE_CATALOG ${catalogSummary(catalog)}');
    nativeMarionetteLog.info(
      'NATIVE_ROUTE desired=${first.diagnostics.desired.captureId}/${first.diagnostics.desired.renderId} '
      'observed=${first.diagnostics.observed.captureId}/${first.diagnostics.observed.renderId}',
    );
    await waitForCapture(first, catalog: catalog);
    await playFixture(first);
    expect(first.diagnostics.playbackAccepted, greaterThan(0));
    expect(identical(first.capture, firstCapture), isTrue);
    final firstIsolation = first.lastIsolation.state;
    await assertObserved(first);
    final firstReceipt = snapshot(first, caseName: 'first-session');

    Map<String, Object?>? osStealReceipt;
    final bluetooth = pairForRoute(catalog, RouteClass.bluetooth);
    final steal =
        pairForRoute(catalog, RouteClass.wired) ??
        pairForRoute(catalog, RouteClass.speakerphone);
    if (bluetooth != null &&
        steal != null &&
        bluetooth.capture != null &&
        steal.capture != null &&
        steal.render != null &&
        steal.capture!.id != bluetooth.capture!.id) {
      await first.select(
        captureId: steal.capture?.id,
        renderId: steal.render?.id,
      );
      await assertObserved(first);
      expect(first.diagnostics.preferenceControlled, isFalse);
      expect(identical(first.capture, firstCapture), isTrue);
      osStealReceipt = snapshot(first, caseName: 'explicit-not-bluetooth');
    }

    final speaker = pairForRoute(catalog, RouteClass.speakerphone);
    final handset = pairForRoute(catalog, RouteClass.handset);
    Map<String, Object?>? routeReceipt;
    if (speaker != null && handset != null) {
      await first.select(
        captureId: speaker.capture?.id,
        renderId: speaker.render?.id,
      );
      await waitForCapture(first);
      await assertObserved(first);
      expect(first.diagnostics.preferenceControlled, isFalse);
      expect(identical(first.capture, firstCapture), isTrue);

      await first.select(
        captureId: handset.capture?.id,
        renderId: handset.render?.id,
      );
      await waitForCapture(first);
      await assertObserved(first);
      expect(identical(first.capture, firstCapture), isTrue);
      routeReceipt = snapshot(first, caseName: 'speaker-handset');
    }

    await first.stop();
    expect(first.isStopped, isTrue);
    expect(manager.session, isNull);

    final afterExplicit = await requireReady(
      manager,
      purpose: 'native-preference',
    );
    expect(
      afterExplicit.diagnostics.preferenceControlled,
      isTrue,
      reason: 'new Session must start from preference, not prior explicit',
    );
    await afterExplicit.stop();
    expect(manager.session, isNull);

    const cycles = 20;
    final cycleFrames = <int>[];
    for (var i = 0; i < cycles; i++) {
      final session = await requireReady(manager, purpose: 'native-cycle-$i');
      final capture = session.capture;
      await waitForCapture(session);
      await playFixture(session);
      expect(identical(session.capture, capture), isTrue);
      expect(session.diagnostics.playbackAccepted, greaterThan(0));
      cycleFrames.add(session.diagnostics.captureFrameCount);
      await session.stop();
      expect(session.isStopped, isTrue);
      expect(manager.session, isNull);
    }

    await writeReceipt({
      'commit': hostCommit(),
      'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
      'os': hostOs(),
      'osVersion': hostOsVersion(),
      'hardware': hostHardware(),
      'permission': 'granted',
      'isolation': firstIsolation.name,
      'catalog': [
        for (final endpoint in catalog)
          {
            'id': endpoint.id,
            'routeClass': endpoint.routeClass.name,
            'isCapture': endpoint.isCapture,
            'pairId': endpoint.pairId,
          },
      ],
      'first': firstReceipt,
      'explicitNotBluetooth': osStealReceipt,
      'speakerHandset': routeReceipt,
      'cycles': cycles,
      'cycleFrames': cycleFrames,
      'nativeFailuresSkipped': false,
    });
  });

  testWidgets('native Marionette: web combinations and devicechange', (
    tester,
  ) async {
    if (!runningOnWeb) {
      return;
    }

    final manager = AudioManager();
    addTearDown(() async {
      await manager.session?.stop();
    });

    var catalog = await manager.endpoints();
    if (catalog.isEmpty) {
      final primed = await requireReady(manager, purpose: 'web-catalog');
      catalog = await manager.endpoints();
      await primed.stop();
    }
    expect(catalog, isNotEmpty);
    final captures = catalog.where((e) => e.isCapture).toList();
    final renders = catalog.where((e) => !e.isCapture).toList();
    expect(captures, isNotEmpty, reason: 'web catalog must list capture');
    expect(renders, isNotEmpty, reason: 'web catalog must list render');

    final combos = <Map<String, Object?>>[];
    for (final capture in captures) {
      for (final render in renders) {
        final session = await requireReady(
          manager,
          purpose: 'web-combo-${capture.id}-${render.id}',
        );
        final captureStream = session.capture;
        await session.select(captureId: capture.id, renderId: render.id);
        await assertObserved(session);
        expect(identical(session.capture, captureStream), isTrue);
        combos.add(snapshot(session, caseName: 'combo'));
        await session.stop();
      }
    }

    final live = await requireReady(manager, purpose: 'web-devicechange');
    final before = await manager.endpoints();
    var devicechange = 'skipped=capability';
    final catalogDeadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(catalogDeadline)) {
      final next = await manager.endpoints();
      if (next.length != before.length ||
          next.map((e) => e.id).join() != before.map((e) => e.id).join()) {
        devicechange = 'catalog-changed';
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await live.stop();

    await writeReceipt({
      'commit': hostCommit(),
      'platform': 'web',
      'os': hostOs(),
      'hardware': hostHardware(),
      'permission': 'granted',
      'combinations': combos,
      'combinationCount': combos.length,
      'devicechange': devicechange,
      'nativeFailuresSkipped': false,
    });
  });

  testWidgets('native Marionette: desktop capture x render combinations', (
    tester,
  ) async {
    if (runningOnWeb) {
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        break;
      default:
        return;
    }

    final manager = AudioManager();
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
    final captures = catalog.where((e) => e.isCapture).toList();
    final renders = catalog.where((e) => !e.isCapture).toList();
    expect(captures, isNotEmpty, reason: 'desktop catalog must list capture');
    expect(renders, isNotEmpty, reason: 'desktop catalog must list render');

    final combos = <Map<String, Object?>>[];
    for (final capture in captures) {
      for (final render in renders) {
        final session = await requireReady(
          manager,
          purpose: 'desktop-combo-${capture.id}-${render.id}',
        );
        final captureStream = session.capture;
        await session.select(captureId: capture.id, renderId: render.id);
        await assertObserved(session);
        expect(identical(session.capture, captureStream), isTrue);
        combos.add(snapshot(session, caseName: 'combo'));
        await session.stop();
      }
    }

    await writeReceipt({
      'commit': hostCommit(),
      'platform': defaultTargetPlatform.name,
      'os': hostOs(),
      'hardware': hostHardware(),
      'permission': 'granted',
      'combinations': combos,
      'combinationCount': combos.length,
      'nativeFailuresSkipped': false,
    });
  });
}
