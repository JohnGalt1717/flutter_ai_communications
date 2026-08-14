import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCommunicationsPlatform platform;
  late AudioManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = AudioManager(platform: platform);
  });

  tearDown(() async {
    await manager.session?.stop();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('Marionette Audio manager can start, mute, pause, and see Isolation',
      () async {
    final result = await manager.start();
    expect(result, isA<StartReady>());
    final session = (result as StartReady).session;
    expect(session.lastIsolation.state, IsolationState.off);
    session.mute();
    expect(session.isMuted, isTrue);
    await session.pause();
    expect(session.isPaused, isTrue);
  });

  test('Marionette shell keys exist on SessionPage', () {
    const start = Key('start');
    const mute = Key('mute');
    const pause = Key('pause');
    expect(const ExampleApp().manager, isNull);
    expect(start, isNot(mute));
    expect(pause, isNot(start));
  });
}
