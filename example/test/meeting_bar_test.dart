import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCommunicationsPlatform platform;
  late CommunicationsManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    Session.teardownTimeout = Duration.zero;
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = CommunicationsManager(
      platform: platform,
      coverageSource: const AlwaysOkCoverageSource(),
    );
  });

  tearDown(() async {
    await manager.session?.stop();
    Session.teardownTimeout = const Duration(seconds: 2);
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  Future<void> pumpMeeting(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ExampleApp(manager: manager));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('lobby-enter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('lobby-join')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Share opens a picker then the same control stops share', (
    tester,
  ) async {
    await pumpMeeting(tester);

    expect(find.byKey(const Key('screen-share')), findsOneWidget);
    expect(find.byKey(const Key('screen-stop')), findsNothing);

    await tester.tap(find.byKey(const Key('screen-share')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('share-picker')), findsOneWidget);
    expect(find.byKey(const Key('screen-source-display-0')), findsOneWidget);
    expect(
      find.byKey(const Key('screen-source-window-notepad')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('screen-source-window-notepad')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(manager.session?.isScreenSending, isTrue);
    expect(find.byKey(const Key('share-picker')), findsNothing);
    expect(find.byKey(const Key('screen-share')), findsNothing);
    expect(find.byKey(const Key('screen-stop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('screen-stop')));
    await tester.pump();
    expect(manager.session?.isScreenSending, isFalse);
    expect(find.byKey(const Key('screen-share')), findsOneWidget);
  });

  testWidgets('camera-pick selects a Camera Endpoint on the live Session', (
    tester,
  ) async {
    await pumpMeeting(tester);
    expect(manager.session?.selectedCameraId, 'front');

    await tester.tap(find.byKey(const Key('camera-pick')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('camera-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('camera-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(manager.session?.selectedCameraId, 'back');
  });

  testWidgets('processor-pick applies blur on the live Session', (
    tester,
  ) async {
    await pumpMeeting(tester);

    await tester.tap(find.byKey(const Key('processor-pick')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('processor-blur-50')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      manager.session?.videoProcessor,
      const BlurVideoProcessor(intensity: 50),
    );
  });
}
