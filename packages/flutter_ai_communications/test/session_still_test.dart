import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeCommunicationsPlatform platform;
  late CommunicationsManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = CommunicationsManager(platform: platform);
  });

  tearDown(() async {
    await manager.session?.stop();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('captureStill samples the camera Production path', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    final result = await session.captureStill();
    expect(result, isA<StillReady>());
    final ready = result as StillReady;
    expect(ready.bytes, FakeCommunicationsPlatform.fixtureJpeg);
    expect(ready.bytes.first, 0xFF);
    expect(ready.bytes[1], 0xD8);
    expect(ready.mime, 'image/jpeg');
    expect(ready.width, 1280);
    expect(ready.height, 720);
    expect(platform.captureStillCalls, 1);
  });

  test('captureStill fails closed when Camera-off', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    await session.setCameraEnabled(false);
    expect(await session.captureStill(), isA<StillUnavailable>());
    expect(platform.captureStillCalls, 0);
    expect(session.isStopped, isFalse);
  });

  test(
    'captureScreenStill fails closed when screen send is not running',
    () async {
      final session =
          ((await manager.start(cameraSend: true)) as StartReady).session;
      expect(await session.captureScreenStill(), isA<StillUnavailable>());
      expect(platform.captureScreenStillCalls, 0);
    },
  );

  test('captureScreenStill samples the screen-send Production path', () async {
    final session = ((await manager.start()) as StartReady).session;
    await session.startScreenShare('display-0');
    final result = await session.captureScreenStill();
    expect(result, isA<StillReady>());
    final ready = result as StillReady;
    expect(ready.bytes, FakeCommunicationsPlatform.fixtureJpeg);
    expect(ready.mime, 'image/jpeg');
    expect(ready.width, 1920);
    expect(ready.height, 1080);
    expect(platform.captureScreenStillCalls, 1);
  });

  test('captureScreenStill fails closed after stopScreenShare', () async {
    final session = ((await manager.start()) as StartReady).session;
    await session.startScreenShare('display-0');
    await session.stopScreenShare();
    expect(await session.captureScreenStill(), isA<StillUnavailable>());
    expect(platform.captureScreenStillCalls, 0);
  });

  test(
    'native still throw is StillFailed and does not end the Session',
    () async {
      platform.stillThrow = StateError('native');
      final session =
          ((await manager.start(cameraSend: true)) as StartReady).session;
      final result = await session.captureStill();
      expect(result, isA<StillFailed>());
      expect(session.isStopped, isFalse);
    },
  );
}
