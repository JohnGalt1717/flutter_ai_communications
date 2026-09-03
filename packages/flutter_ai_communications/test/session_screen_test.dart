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

  test('screenSources() works while idle', () async {
    final sources = await manager.screenSources();
    expect(sources.map((source) => source.id), [
      'display-0',
      'window-notepad',
      'all-displays',
      'system-picker',
    ]);
  });

  test('lobby cannot open Screen pick or start screen send', () async {
    final session =
        ((await manager.start(purpose: 'lobby')) as StartReady).session;
    expect(await session.beginScreenPick(), isA<ScreenPickBlocked>());
    expect(
      await session.startScreenShare('display-0'),
      isA<ScreenShareBlocked>(),
    );
    expect(session.isScreenSending, isFalse);
    expect(platform.startScreenShareCalls, 0);
  });

  test('start() does not request screen permission or auto-share', () async {
    final session = ((await manager.start()) as StartReady).session;
    expect(platform.screenPermissionRequests, 0);
    expect(session.isScreenSending, isFalse);
    expect(session.settings.purpose, isNull);
  });

  test('meeting pick then share yields a second Video surface', () async {
    final session =
        ((await manager.start(purpose: 'meeting', cameraSend: true))
                as StartReady)
            .session;
    expect(session.videoSurface?.handle, 1);
    final pick = await session.beginScreenPick();
    expect(pick, isA<ScreenPickReady>());
    expect(session.screenPreview('display-0'), isNotNull);
    await session.indicateScreenSource('display-0');
    expect(platform.indicatedScreenSourceId, 'display-0');
    final share = await session.startScreenShare('display-0');
    expect(share, isA<ScreenShareReady>());
    expect(session.isScreenSending, isTrue);
    expect(session.screenSurface?.handle, 2);
    expect(session.videoSurface?.handle, 1);
    expect(session.screenNativeFormat?.frameRate, 5);
    expect(session.isScreenPickOpen, isFalse);
  });

  test('denied screen permission does not end the Session', () async {
    platform.screenPermission = ScreenPermission.denied;
    final session = ((await manager.start()) as StartReady).session;
    final share = await session.startScreenShare('display-0');
    expect(share, isA<ScreenShareDenied>());
    expect(session.isStopped, isFalse);
    expect(session.screenUnavailableReason, 'denied');
  });

  test('replace startScreenShare does not require stop first', () async {
    final session = ((await manager.start()) as StartReady).session;
    await session.startScreenShare('display-0');
    await session.startScreenShare('window-notepad', motion: true);
    expect(session.isScreenSending, isTrue);
    expect(platform.startScreenShareCalls, 2);
    expect(session.isScreenMotion, isTrue);
  });

  test('includeSystemAudio is not the mic Capture stream', () async {
    final session = ((await manager.start()) as StartReady).session;
    final capture = session.capture;
    await session.startScreenShare('display-0', includeSystemAudio: true);
    expect(identical(session.capture, capture), isTrue);
    expect(session.includeSystemAudio, isTrue);
    expect(session.isMuted, isFalse);
    session.mute();
    expect(session.isMuted, isTrue);
    expect(session.includeSystemAudio, isTrue);
  });

  test('system audio failure is a warning, share stays up', () async {
    platform.systemAudioAvailable = false;
    final session = ((await manager.start()) as StartReady).session;
    final share = await session.startScreenShare(
      'display-0',
      includeSystemAudio: true,
    );
    expect(share, isA<ScreenShareReady>());
    expect(session.includeSystemAudio, isFalse);
    expect(session.status.code, SessionStatusCode.screenAudioUnavailable);
  });

  test('Camera-off does not stop screen send', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    await session.startScreenShare('display-0');
    await session.setCameraEnabled(false);
    expect(session.isCameraEnabled, isFalse);
    expect(session.isScreenSending, isTrue);
    expect(session.screenSurface, isNotNull);
  });

  test('vanished send source stops screen send, not the Session', () async {
    final session = ((await manager.start()) as StartReady).session;
    await session.startScreenShare('display-0');
    platform.screenSources = platform.screenSources
        .where((source) => source.id != 'display-0')
        .toList();
    platform.screenCatalogController.add(platform.screenSources);
    await Future<void>.delayed(Duration.zero);
    expect(session.isStopped, isFalse);
    expect(session.isScreenSending, isFalse);
    expect(session.status.code, SessionStatusCode.screenNotRunning);
  });

  test('Join settings do not start screen send', () async {
    final lobby =
        ((await manager.start(purpose: 'lobby')) as StartReady).session;
    final settings = lobby.settings;
    await lobby.stop();
    final meeting =
        ((await manager.start(settings: settings, purpose: 'meeting'))
                as StartReady)
            .session;
    expect(meeting.isScreenSending, isFalse);
    expect(platform.startScreenShareCalls, 0);
  });
}
