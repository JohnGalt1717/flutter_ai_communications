import 'package:flutter/foundation.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_orchestration_support.dart';

/// Camera graph proof on a real head. Empty catalog is a skip, not failure.
void main() {
  installNativeOrchestrationLogging();

  testWidgets('native camera: catalog, Texture, Mute-video, Camera-off', (
    tester,
  ) async {
    final manager = CommunicationsManager();
    addTearDown(() async {
      await manager.session?.stop();
    });

    final platform = FlutterAiCommunicationsPlatform.instance;
    final permission = await platform.requestCameraPermission();
    nativeOrchestrationLog.info(
      'NATIVE_CAMERA_PERMISSION result=${permission.name}',
    );
    expect(permission, CameraPermission.granted);

    final cameras = await manager.cameras();
    nativeOrchestrationLog.info(
      'NATIVE_CAMERAS count=${cameras.length} '
      '${cameras.map((camera) => '${camera.id}:${camera.name}:${camera.facing.name}').join(' | ')}',
    );
    if (cameras.isEmpty) {
      nativeOrchestrationLog.info('NATIVE_SKIP camera=none');
      await writeReceipt({
        'commit': hostCommit(),
        'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
        'os': hostOs(),
        'osVersion': hostOsVersion(),
        'hardware': hostHardware(),
        'cameras': const <Object>[],
        'skipped': 'none',
      });
      return;
    }

    final lobby = await requireReady(
      manager,
      purpose: 'lobby',
      cameraSend: true,
    );
    expect(lobby.videoUnavailableReason, isNull);
    expect(lobby.videoSurface, isNotNull);
    expect(lobby.nativeVideoFormat, isNotNull);
    expect(lobby.isCameraEnabled, isTrue);
    final lobbyCapture = lobby.capture;
    nativeOrchestrationLog.info(
      'NATIVE_CAMERA_SURFACE handle=${lobby.videoSurface?.handle} '
      'format=${lobby.nativeVideoFormat} id=${lobby.selectedCameraId}',
    );
    await waitForCameraStream(platform);
    await platform.pollCameraNative();
    final liveBeforeOff = platform.lastCameraFrameCount;

    await lobby.setCameraEnabled(false);
    expect(lobby.isSendingVideo, isFalse);
    expect(identical(lobby.capture, lobbyCapture), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await platform.pollCameraNative();
    expect(
      platform.lastCameraFrameCount,
      lessThanOrEqualTo(liveBeforeOff + 2),
      reason: 'Camera-off must stop native capture frames',
    );

    await lobby.setCameraEnabled(true);
    expect(lobby.videoSurface, isNotNull);
    expect(identical(lobby.capture, lobbyCapture), isTrue);
    await waitForCameraStream(platform);

    if (cameras.length > 1) {
      final other = cameras.firstWhere(
        (camera) => camera.id != lobby.selectedCameraId,
        orElse: () => cameras.last,
      );
      await lobby.selectCamera(other.id);
      expect(lobby.selectedCameraId, other.id);
      expect(identical(lobby.capture, lobbyCapture), isTrue);
    }

    final settings = lobby.settings;
    await lobby.stop();
    expect(manager.session, isNull);

    final joined = await manager.start(settings: settings, purpose: 'meeting');
    expect(joined, isA<StartReady>());
    final meeting = (joined as StartReady).session;
    expect(meeting.videoSurface, isNotNull);
    expect(identical(meeting, lobby), isFalse);
    await waitForCameraStream(platform);
    await meeting.muteVideo();
    expect(meeting.isVideoMuted, isTrue);
    expect(meeting.isSendingVideo, isTrue);
    await platform.pollCameraNative();
    final mutedFrames = platform.lastCameraFrameCount;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await platform.pollCameraNative();
    expect(
      platform.lastCameraFrameCount,
      greaterThan(mutedFrames),
      reason: 'Mute-video keeps the native graph capturing',
    );
    await meeting.unmuteVideo();
    expect(meeting.isVideoMuted, isFalse);
    await meeting.stop();

    final audio = await requireReady(manager, purpose: 'audio-then-video');
    final audioCapture = audio.capture;
    await audio.enableVideo(cameraId: cameras.first.id);
    expect(audio.videoSurface, isNotNull);
    expect(identical(audio.capture, audioCapture), isTrue);
    expect(audio.videoUnavailableReason, isNull);
    await waitForCameraStream(platform);
    await audio.stop();

    await writeReceipt({
      'commit': hostCommit(),
      'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
      'os': hostOs(),
      'osVersion': hostOsVersion(),
      'hardware': hostHardware(),
      'permission': permission.name,
      'streamFrames': platform.lastCameraFrameCount,
      'streamLiveFrames': platform.lastCameraLiveFrames,
      'cameras': [
        for (final camera in cameras)
          {
            'id': camera.id,
            'name': camera.name,
            'facing': camera.facing.name,
          },
      ],
      'lobby': snapshot(lobby, caseName: 'lobby'),
      'meetingMuted': true,
      'enableVideoLater': true,
      'captureIdentityHeld': true,
      'settingsCameraId': settings.cameraId,
    });
  });
}
