import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/main.dart';
import 'package:flutter_ai_communications_example/meeting/host_webrtc_loopback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCommunicationsPlatform platform;
  late CommunicationsManager manager;
  late FakeHostWebRtcLoopback loopback;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    Session.teardownTimeout = Duration.zero;
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = CommunicationsManager(
      platform: platform,
      coverageSource: const AlwaysOkCoverageSource(),
    );
    loopback = FakeHostWebRtcLoopback();
  });

  tearDown(() async {
    await loopback.dispose();
    await manager.cameraPreview?.stop();
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
    await tester.pumpWidget(
      ExampleApp(manager: manager, webRtcLoopback: loopback),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('lobby-enter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('lobby-join')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Join addTracks the Send track and shows inbound video', (
    tester,
  ) async {
    await pumpMeeting(tester);

    expect(loopback.addedTrackIds, ['video-1']);
    expect(loopback.lastTrack?.muteVideo, isFalse);
    expect(find.byKey(inboundKey), findsOneWidget);
    expect(find.byKey(const Key('self-view')), findsOneWidget);
  });

  testWidgets('Camera-off removes the Send track; Mute-video keeps it', (
    tester,
  ) async {
    await pumpMeeting(tester);
    expect(loopback.lastTrack, isNotNull);

    await tester.tap(find.byKey(const Key('mute-video')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(loopback.lastTrack, isNotNull);
    expect(loopback.lastTrack!.muteVideo, isTrue);
    expect(loopback.removedTrackIds, isEmpty);

    await tester.tap(find.byKey(const Key('camera-off')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(loopback.lastTrack, isNull);
    expect(loopback.removedTrackIds, ['video-1']);
    expect(manager.session?.isStopped, isFalse);
  });

  testWidgets('Leave detaches the loopback and does not leak the Session', (
    tester,
  ) async {
    await pumpMeeting(tester);
    expect(manager.session, isNotNull);

    await tester.tap(find.byTooltip('Leave'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(loopback.disposed, isTrue);
    await manager.session?.stop();
    expect(manager.session, isNull);
  });
}
