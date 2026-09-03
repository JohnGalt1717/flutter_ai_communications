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

  test(
    'Orchestration Audio manager can start, mute, pause, and see Isolation',
    () async {
      final result = await manager.start();
      expect(result, isA<StartReady>());
      final session = (result as StartReady).session;
      expect(session.lastIsolation.state, IsolationState.required);
      session.mute();
      expect(session.isMuted, isTrue);
      await session.pause();
      expect(session.isPaused, isTrue);
    },
  );

  test('Orchestration shell keys exist on SessionPage', () {
    const enter = Key('lobby-enter');
    const join = Key('lobby-join');
    const mute = Key('mute');
    const pause = Key('pause');
    expect(const ExampleApp().manager, isNull);
    expect(enter, isNot(mute));
    expect(join, isNot(enter));
    expect(pause, isNot(enter));
    expect(const Key('prove'), isNot(enter));
    expect(const Key('pipeline-log'), isNot(enter));
    expect(const Key('desired-capture'), isNot(const Key('observed-capture')));
    expect(const Key('generation'), isNot(const Key('status')));
    expect(const Key('lobby'), isNot(const Key('meeting')));
  });

  testWidgets(
    'Orchestration debug keys prove Desired/Applied/Observed and logs',
    (tester) async {
      await tester.pumpWidget(ExampleApp(manager: manager));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('lobby')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lobby-enter')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.byKey(const Key('desired-capture')), findsOneWidget);
      expect(find.byKey(const Key('applied-capture')), findsOneWidget);
      expect(find.byKey(const Key('observed-capture')), findsOneWidget);
      expect(find.byKey(const Key('generation')), findsOneWidget);
      expect(find.byKey(const Key('status-code')), findsOneWidget);
      expect(find.byKey(const Key('status-recoverability')), findsOneWidget);
      expect(find.byKey(const Key('status-usability')), findsOneWidget);
      expect(find.byKey(const Key('status-attempt')), findsOneWidget);
      expect(find.byKey(const Key('status-max-attempts')), findsOneWidget);
      expect(find.byKey(const Key('pipeline-log')), findsOneWidget);
      expect(find.byKey(const Key('capture-frames')), findsOneWidget);
      expect(find.byKey(const Key('playback-progress')), findsOneWidget);
      expect(find.byKey(const Key('native-capture-format')), findsOneWidget);
      expect(find.byKey(const Key('capture-conversion-path')), findsOneWidget);
      expect(find.byKey(const Key('acoustic-profile')), findsOneWidget);
      expect(find.byKey(const Key('capture-processor')), findsOneWidget);
      expect(find.byKey(const Key('active-floor')), findsOneWidget);
      expect(
        (find
                    .byKey(const Key('capture-conversion-path'))
                    .evaluate()
                    .single
                    .widget
                as Text)
            .data,
        ConversionPath.identity.name,
      );
      expect(
        (find.byKey(const Key('desired-capture')).evaluate().single.widget
                as Text)
            .data,
        'airpods-in',
      );
      expect(
        (find.byKey(const Key('pipeline-log')).evaluate().single.widget as Text)
            .data,
        contains(PipelineLog.startRequested),
      );
      expect(
        (find.byKey(const Key('pipeline-log')).evaluate().single.widget as Text)
            .data,
        contains(PipelineLog.isolation),
      );
      expect(
        (find.byKey(const Key('isolation')).evaluate().single.widget as Text)
            .data,
        contains(IsolationState.required.name),
      );
      expect(
        (find.byKey(const Key('playback-progress')).evaluate().single.widget
                as Text)
            .data,
        '0/0/0/0',
      );
      expect(find.byKey(const Key('lobby-join')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lobby-join')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const Key('meeting')), findsOneWidget);
      expect(find.byKey(const Key('prove')), findsOneWidget);
      expect(
        (find.byKey(const Key('direction')).evaluate().single.widget as Text)
            .data,
        contains('meeting'),
      );

      await manager.session?.stop();
      await tester.pump(Duration.zero);
    },
  );

  testWidgets('lobby Session exposes camera keys and self-view', (tester) async {
    await tester.pumpWidget(ExampleApp(manager: manager));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('lobby-enter')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.scrollUntilVisible(find.byKey(const Key('self-view')), 80);
    expect(find.byKey(const Key('self-view')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('camera-front')), 80);
    expect(find.byKey(const Key('camera-front')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('camera-off')), 80);
    expect(find.byKey(const Key('camera-off')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('lobby-join')), -300);
    await tester.tap(find.byKey(const Key('lobby-join')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.scrollUntilVisible(find.byKey(const Key('mute-video')), 80);
    expect(find.byKey(const Key('mute-video')), findsOneWidget);
    await manager.session?.muteVideo();
    expect(manager.session?.isVideoMuted, isTrue);
    await manager.session?.setCameraEnabled(false);
    expect(manager.session?.isCameraEnabled, isFalse);
    await manager.session?.stop();
    await tester.pump(Duration.zero);
  });
}
