import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/host_preference_store.dart';
import 'package:flutter_ai_communications_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCommunicationsPlatform platform;
  late CommunicationsManager manager;
  late HostPreferenceStore store;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    Session.teardownTimeout = Duration.zero;
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = CommunicationsManager(
      platform: platform,
      coverageSource: const AlwaysOkCoverageSource(),
    );
    store = HostPreferenceStore();
  });

  tearDown(() async {
    await manager.cameraPreview?.stop();
    await manager.session?.stop();
    Session.teardownTimeout = const Duration(seconds: 2);
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  Future<void> pumpHarness(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ExampleApp(manager: manager, preferenceStore: store),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> enterLobby(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('lobby-enter')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('idle camera tap writes Camera preference and start binds it', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('camera-back')), 80);
    await tester.tap(find.byKey(const Key('camera-back')));
    await tester.pump();

    expect(store.cameras.entries.map((entry) => entry.id), ['back']);
    expect(store.endpoints.isEmpty, isTrue);
    expect(manager.boundCameraPreference.entries.single.id, 'back');

    await tester.scrollUntilVisible(find.byKey(const Key('lobby-enter')), -80);
    await enterLobby(tester);
    expect(manager.session?.selectedCameraId, 'back');
  });

  testWidgets('mid-session camera select does not write Camera preference', (
    tester,
  ) async {
    store.preferCamera('front');
    await pumpHarness(tester);
    await enterLobby(tester);
    expect(manager.session?.selectedCameraId, 'front');

    await tester.scrollUntilVisible(find.byKey(const Key('camera-back')), 80);
    await tester.tap(find.byKey(const Key('camera-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(manager.session?.selectedCameraId, 'back');
    expect(store.cameras.entries.single.id, 'front');
    expect(manager.boundCameraPreference.entries.single.id, 'front');
  });

  testWidgets('unplug walks the stored Camera preference at start', (
    tester,
  ) async {
    store.preferCamera('front');
    store.preferCamera('back');
    platform.cameras = [
      FakeCommunicationsPlatform.defaultCameras.firstWhere(
        (camera) => camera.id == 'front',
      ),
    ];
    await pumpHarness(tester);
    await enterLobby(tester);
    expect(manager.session?.selectedCameraId, 'front');
    expect(store.cameras.entries.map((entry) => entry.id), ['back', 'front']);
  });

  testWidgets(
    'idle Endpoint highlight is the first stored capture and render',
    (tester) async {
      store.preferEndpoint(
        FakeCommunicationsPlatform.defaultCatalog.firstWhere(
          (endpoint) => endpoint.id == 'speaker-in',
        ),
        FakeCommunicationsPlatform.defaultCatalog,
      );
      store.preferEndpoint(
        FakeCommunicationsPlatform.defaultCatalog.firstWhere(
          (endpoint) => endpoint.id == 'handset-out',
        ),
        FakeCommunicationsPlatform.defaultCatalog,
      );
      await pumpHarness(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('endpoint-handset-out')),
        80,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('endpoint-handset-out')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('endpoint-handset-in')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('endpoint-speaker-in')))
            .selected,
        isFalse,
      );
    },
  );

  testWidgets(
    'idle Endpoint tap writes Endpoint preference and start binds it',
    (tester) async {
      await pumpHarness(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('endpoint-speaker-in')),
        80,
      );
      await tester.tap(find.byKey(const Key('endpoint-speaker-in')));
      await tester.pump();

      expect(store.endpoints.entries.single.renderId, 'speaker-out');
      expect(store.endpoints.entries.single.captures.single.id, 'speaker-in');
      expect(store.cameras.isEmpty, isTrue);
      expect(manager.boundPreference.entries.single.renderId, 'speaker-out');

      await tester.scrollUntilVisible(
        find.byKey(const Key('lobby-enter')),
        -80,
      );
      await enterLobby(tester);
      expect(manager.session?.selectedCaptureId, 'speaker-in');
      expect(manager.session?.selectedRenderId, 'speaker-out');
      expect(manager.session?.diagnostics.preferenceControlled, isTrue);
    },
  );

  testWidgets(
    'mid-session Endpoint select does not write Endpoint preference',
    (tester) async {
      store.preferEndpoint(
        FakeCommunicationsPlatform.defaultCatalog.firstWhere(
          (endpoint) => endpoint.id == 'airpods-in',
        ),
        FakeCommunicationsPlatform.defaultCatalog,
      );
      await pumpHarness(tester);
      await enterLobby(tester);
      expect(manager.session?.selectedCaptureId, 'airpods-in');

      await tester.scrollUntilVisible(
        find.byKey(const Key('endpoint-speaker-in')),
        80,
      );
      await tester.tap(find.byKey(const Key('endpoint-speaker-in')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(manager.session?.selectedCaptureId, 'speaker-in');
      expect(store.endpoints.entries.single.renderId, 'airpods-out');
      expect(manager.boundPreference.entries.single.renderId, 'airpods-out');
      expect(manager.session?.diagnostics.preferenceControlled, isFalse);
    },
  );

  testWidgets('Camera preview binds stored Camera preference', (tester) async {
    store.preferCamera('back');
    await pumpHarness(tester);
    await enterLobby(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('camera-off')), 80);
    await tester.tap(find.byKey(const Key('camera-off')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('camera-preview')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(manager.cameraPreview?.selectedCameraId, 'back');
    expect(store.cameras.entries.single.id, 'back');
  });

  testWidgets('Camera preview binds stored list after an ephemeral live pick', (
    tester,
  ) async {
    store.preferCamera('back');
    await pumpHarness(tester);
    await enterLobby(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('camera-front')), 80);
    await tester.tap(find.byKey(const Key('camera-front')));
    await tester.pump();
    expect(manager.session?.selectedCameraId, 'front');
    expect(store.cameras.entries.single.id, 'back');

    await tester.scrollUntilVisible(find.byKey(const Key('camera-off')), -80);
    await tester.tap(find.byKey(const Key('camera-off')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('camera-preview')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(manager.cameraPreview?.selectedCameraId, 'back');
    expect(store.cameras.entries.single.id, 'back');
  });

  testWidgets('editor Apply persists Endpoint preference', (tester) async {
    await pumpHarness(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('pref-row-enable-airpods-out')),
      80,
    );
    await tester.tap(find.byKey(const Key('pref-row-enable-airpods-out')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pref-apply')));
    await tester.pump();

    expect(
      store.endpoints.entries.any(
        (entry) => entry.renderId == 'airpods-out' && !entry.enabled,
      ),
      isTrue,
    );
    expect(manager.boundPreference.entries, isNotEmpty);
  });
}
