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
    await manager.cameraPreview?.stop();
    await manager.session?.stop();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('cameras() works while idle', () async {
    final cameras = await manager.cameras();
    expect(cameras.map((camera) => camera.id), ['front', 'back']);
  });

  test('missing camera does not fail start', () async {
    platform.cameras = [];
    final result = await manager.start(cameraSend: true);
    expect(result, isA<StartReady>());
    final session = (result as StartReady).session;
    expect(session.videoUnavailableReason, 'none');
    expect(session.videoSurface, isNull);
    expect(session.capture, isNotNull);
  });

  test('camera denied does not fail start', () async {
    platform.cameraPermission = CameraPermission.denied;
    final result = await manager.start(cameraSend: true);
    expect(result, isA<StartReady>());
    expect((result as StartReady).session.videoUnavailableReason, 'denied');
  });

  test('granted camera yields a Video surface and nearest Native Video Format', () async {
    final result = await manager.start(cameraSend: true);
    final session = (result as StartReady).session;
    expect(session.videoSurface?.handle, 1);
    expect(session.selectedCameraId, 'front');
    expect(session.nativeVideoFormat, VideoFormat.defaultFormat);
    expect(session.videoUnavailableReason, isNull);
  });

  test('Mute-video keeps the surface; Camera-off clears it', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    expect(session.isSendingVideo, isTrue);
    await session.muteVideo();
    expect(session.isVideoMuted, isTrue);
    expect(session.isSendingVideo, isTrue);
    expect(platform.muteVideo, isTrue);
    await session.setCameraEnabled(false);
    expect(session.isCameraEnabled, isFalse);
    expect(session.isSendingVideo, isFalse);
    expect(session.videoSurface, isNull);
    expect(platform.cameraEnabled, isFalse);
  });

  test('selectCamera is ephemeral and does not write Camera preference', () async {
    manager.bindCameraPreference(
      const CameraPreference(entries: [CameraPreferenceEntry(id: 'front')]),
    );
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    await session.selectCamera('back');
    expect(session.selectedCameraId, 'back');
    expect(manager.boundCameraPreference.entries.single.id, 'front');
  });

  test('Camera preview is blocked while the Session is sending video', () async {
    await manager.start(cameraSend: true);
    final preview = await manager.startCameraPreview();
    expect(preview, isA<PreviewBlocked>());
  });

  test('Camera preview starts after Camera-off', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    await session.setCameraEnabled(false);
    final preview = await manager.startCameraPreview();
    expect(preview, isA<PreviewReady>());
    expect((preview as PreviewReady).preview.surface.handle, 1);
  });

  test('enableVideo later does not replace the Capture stream', () async {
    final session = ((await manager.start()) as StartReady).session;
    final capture = session.capture;
    await session.enableVideo();
    expect(identical(session.capture, capture), isTrue);
    expect(session.videoSurface, isNotNull);
  });

  test('Session settings round-trip into a new Session after stop', () async {
    final lobby =
        ((await manager.start(purpose: 'lobby', cameraSend: true))
                as StartReady)
            .session;
    await lobby.selectCamera('back');
    lobby.mute();
    final settings = lobby.settings;
    await lobby.stop();
    final meeting =
        ((await manager.start(settings: settings, purpose: 'meeting'))
                as StartReady)
            .session;
    expect(meeting.purpose, 'meeting');
    expect(meeting.selectedCameraId, 'back');
    expect(meeting.isMuted, isTrue);
    expect(identical(meeting, lobby), isFalse);
  });

  test('bindCameraPreference does not stop a live Session', () async {
    final session = ((await manager.start()) as StartReady).session;
    manager.bindCameraPreference(
      const CameraPreference(entries: [CameraPreferenceEntry(id: 'back')]),
    );
    expect(session.isStopped, isFalse);
    expect(manager.session, session);
  });
}
