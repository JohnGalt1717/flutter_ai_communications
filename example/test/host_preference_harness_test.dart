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
    tester.view.physicalSize = const Size(800, 8000);
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

  testWidgets('SessionPage starts in the lobby Session', (tester) async {
    await pumpHarness(tester);
    await tester.pump(const Duration(milliseconds: 1));
    expect(manager.session, isNotNull);
    expect(manager.session?.purpose, 'lobby');
    expect(find.byKey(const Key('lobby')), findsOneWidget);
    expect(find.byKey(const Key('meeting')), findsNothing);
    expect(find.byKey(const Key('lobby-join')), findsOneWidget);
    expect(find.byKey(const Key('visualizer')), findsOneWidget);
  });

  testWidgets('lobby audio picker dismisses when tapping outside', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('audio-pick')));
    await tester.pump();
    expect(find.byKey(const Key('audio-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('flyout-dismiss')));
    await tester.pump();
    expect(find.byKey(const Key('audio-panel')), findsNothing);
  });

  testWidgets('mid-session camera select does not write Camera preference', (
    tester,
  ) async {
    store.preferCamera('front');
    await pumpHarness(tester);
    await enterLobby(tester);
    expect(manager.session?.selectedCameraId, 'front');

    await tester.tap(find.byKey(const Key('camera-pick')));
    await tester.pump();
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
    'stored Endpoint preference is selected when the lobby Session starts',
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
      await tester.pump(const Duration(milliseconds: 1));
      expect(manager.session?.selectedCaptureId, 'handset-in');
      expect(manager.session?.selectedRenderId, 'handset-out');
      await tester.tap(find.byKey(const Key('audio-pick')));
      await tester.pump();
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
    'lobby Endpoint tap is Explicit selection and does not write preference',
    (tester) async {
      await pumpHarness(tester);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.tap(find.byKey(const Key('audio-pick')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('endpoint-speaker-in')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(manager.session?.selectedCaptureId, 'speaker-in');
      expect(store.endpoints.isEmpty, isTrue);
      expect(manager.session?.diagnostics.preferenceControlled, isFalse);
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

      await tester.tap(find.byKey(const Key('audio-pick')));
      await tester.pump();
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
    await tester.tap(find.byKey(const Key('camera-off')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('camera-pick')));
    await tester.pump();
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
    await tester.tap(find.byKey(const Key('camera-pick')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('camera-front')));
    await tester.pump();
    expect(manager.session?.selectedCameraId, 'front');
    expect(store.cameras.entries.single.id, 'back');

    await tester.tap(find.byKey(const Key('camera-off')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('camera-preview')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(manager.cameraPreview?.selectedCameraId, 'back');
    expect(store.cameras.entries.single.id, 'back');
  });

  testWidgets('edge format keys restart the Session at 24 kHz and 16 kHz', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.pump(const Duration(milliseconds: 1));
    expect(manager.session?.captureFormat, AudioFormat.pcm16le24k);
    expect(manager.session?.playbackFormat, AudioFormat.pcm16le24k);
    expect(find.byKey(const Key('edge-format-24k')), findsOneWidget);
    expect(find.byKey(const Key('edge-format-16k')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edge-format-16k')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      manager.session?.captureFormat,
      const AudioFormat.pcm16le(sampleRate: 16000),
    );
    expect(
      manager.session?.playbackFormat,
      const AudioFormat.pcm16le(sampleRate: 16000),
    );
    expect(manager.session?.purpose, 'lobby');

    await tester.tap(find.byKey(const Key('edge-format-24k')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(manager.session?.captureFormat, AudioFormat.pcm16le24k);
    expect(manager.session?.playbackFormat, AudioFormat.pcm16le24k);
  });

  testWidgets('editor Apply persists Endpoint preference', (tester) async {
    await pumpHarness(tester);
    await tester.ensureVisible(
      find.byKey(const Key('pref-row-enable-airpods-out')),
    );
    await tester.pump();
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
