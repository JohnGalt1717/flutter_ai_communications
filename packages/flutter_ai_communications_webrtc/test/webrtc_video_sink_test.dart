import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_webrtc/flutter_ai_communications_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeCommunicationsPlatform platform;
  late CommunicationsManager manager;
  late WebrtcVideoSink sink;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = CommunicationsManager(platform: platform);
    sink = WebrtcVideoSink();
  });

  tearDown(() async {
    sink.detach();
    await manager.cameraPreview?.stop();
    await manager.session?.stop();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test(
    'attach after StartReady yields a Send track on the Production path',
    () async {
      final session =
          ((await manager.start(cameraSend: true)) as StartReady).session;
      final capture = session.capture;
      sink.attach(session);

      expect(sink.localVideo, isNotNull);
      expect(sink.localVideo!.id, 'video-1');
      expect(sink.localVideo!.generation, 1);
      expect(sink.localVideo!.muteVideo, isFalse);
      expect(sink.localVideo!.surface?.handle, 1);
      expect(session.videoSurface?.handle, 1);
      expect(identical(session.capture, capture), isTrue);
    },
  );

  test('Mute-video keeps the Send track; Camera-off clears it', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    sink.attach(session);
    expect(sink.localVideo, isNotNull);

    await session.muteVideo();
    expect(sink.localVideo, isNotNull);
    expect(sink.localVideo!.muteVideo, isTrue);
    expect(sink.localVideo!.id, 'video-1');
    expect(sink.localVideo!.surface, isNotNull);

    await session.setCameraEnabled(false);
    expect(sink.localVideo, isNull);
    expect(session.isStopped, isFalse);
  });

  test(
    'enableVideo later yields a Send track on the same Capture stream',
    () async {
      final session = ((await manager.start()) as StartReady).session;
      final capture = session.capture;
      sink.attach(session);
      expect(sink.localVideo, isNull);

      await session.enableVideo();
      expect(identical(session.capture, capture), isTrue);
      expect(sink.localVideo, isNotNull);
      expect(sink.localVideo!.generation, 1);
      expect(sink.localVideo!.surface, isNotNull);
    },
  );

  test(
    'detach does not end the Session or replace the Capture stream',
    () async {
      final session =
          ((await manager.start(cameraSend: true)) as StartReady).session;
      final capture = session.capture;
      sink.attach(session);
      sink.detach();
      sink.detach();

      expect(sink.localVideo, isNull);
      expect(session.isStopped, isFalse);
      expect(identical(session.capture, capture), isTrue);
      await session.muteVideo();
      expect(sink.localVideo, isNull);
    },
  );

  test('late Send track subscriber receives the current track', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    sink.attach(session);
    WebrtcSendTrack? seen;
    final sub = sink.localVideos.listen((track) => seen = track);
    await Future<void>.delayed(Duration.zero);
    expect(seen?.id, 'video-1');
    await sub.cancel();
  });
}
