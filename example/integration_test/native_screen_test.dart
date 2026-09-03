import 'package:flutter/foundation.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_orchestration_support.dart';

/// Native screen send proof. Never wraps the platform in loopback.
void main() {
  installNativeOrchestrationLogging();

  testWidgets(
    'native screen: catalog, lobby fail-closed, share, camera+screen, cycles',
    (tester) async {
      final platform = FlutterAiCommunicationsPlatform.instance;
      expect(
        platform.runtimeType.toString(),
        isNot(contains('Loopback')),
        reason: 'native suite must not wrap the registered adapter',
      );

      final manager = CommunicationsManager();
      addTearDown(() async {
        await manager.session?.stop();
      });

      final sources = await manager.screenSources();
      nativeOrchestrationLog.info(
        'NATIVE_SCREEN_CATALOG count=${sources.length} '
        '${sources.map(_sourceSummary).join(' | ')}',
      );

      final lobby = await requireReady(manager, purpose: 'lobby');
      final lobbyShareId = sources.isEmpty ? 'none' : sources.first.id;
      expect(await lobby.beginScreenPick(), isA<ScreenPickBlocked>());
      expect(
        await lobby.startScreenShare(lobbyShareId),
        isA<ScreenShareBlocked>(),
      );
      expect(lobby.isScreenSending, isFalse);
      await lobby.stop();
      expect(manager.session, isNull);

      if (sources.isEmpty) {
        nativeOrchestrationLog.info('NATIVE_SKIP screen=none');
        await writeReceipt({
          'commit': hostCommit(),
          'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
          'os': hostOs(),
          'osVersion': hostOsVersion(),
          'hardware': hostHardware(),
          'sources': const <Object>[],
          'lobbyBlocked': true,
          'skipped': 'none',
        });
        return;
      }

      final enumerable = [
        for (final source in sources)
          if (source.kind != ScreenSourceKind.systemPicker) source,
      ];
      if (enumerable.isEmpty) {
        nativeOrchestrationLog.info('NATIVE_SKIP screen=os-picker');
        await writeReceipt({
          'commit': hostCommit(),
          'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
          'os': hostOs(),
          'osVersion': hostOsVersion(),
          'hardware': hostHardware(),
          'sources': [for (final source in sources) _sourceMap(source)],
          'lobbyBlocked': true,
          'skipped': 'os-picker',
        });
        return;
      }

      final source = enumerable.where((item) {
        return item.kind == ScreenSourceKind.display;
      }).firstOrNull ?? enumerable.first;

      final meeting = await requireReady(
        manager,
        purpose: 'meeting',
        cameraSend: true,
      );
      expect(meeting.isScreenSending, isFalse);
      final meetingCapture = meeting.capture;
      final cameraSurface = meeting.videoSurface;

      final pick = await meeting.beginScreenPick();
      expect(pick, isA<ScreenPickReady>());
      await meeting.indicateScreenSource(source.id);
      final share = await meeting.startScreenShare(source.id);
      expect(
        share,
        isA<ScreenShareReady>(),
        reason: 'enumerable share must start ($share '
            'reason=${meeting.screenUnavailableReason})',
      );
      expect(meeting.isScreenSending, isTrue);
      expect(meeting.screenSurface, isNotNull);
      expect(identical(meeting.capture, meetingCapture), isTrue);
      nativeOrchestrationLog.info(
        'NATIVE_SCREEN_SURFACE handle=${meeting.screenSurface?.handle} '
        'format=${meeting.screenNativeFormat} id=${meeting.selectedScreenSourceId}',
      );

      if (cameraSurface != null) {
        expect(meeting.videoSurface?.handle, cameraSurface.handle);
        expect(
          meeting.screenSurface!.handle,
          isNot(cameraSurface.handle),
          reason: 'camera and screen are two Production video paths',
        );
        await meeting.setCameraEnabled(false);
        expect(meeting.isScreenSending, isTrue);
        await meeting.setCameraEnabled(true);
        expect(meeting.isScreenSending, isTrue);
      }

      await meeting.setIncludeSystemAudio(true);
      final includeSound = meeting.includeSystemAudio;
      nativeOrchestrationLog.info(
        'NATIVE_SCREEN_AUDIO includeSystemAudio=$includeSound',
      );
      await meeting.setScreenMotion(true);
      expect(meeting.isScreenMotion, isTrue);
      await meeting.setScreenMotion(false);
      await meeting.setScreenCursor(false);
      expect(meeting.isScreenCursor, isFalse);
      await meeting.setScreenCursor(true);

      await meeting.stopScreenShare();
      expect(meeting.isScreenSending, isFalse);
      expect(meeting.screenSurface, isNull);
      expect(identical(meeting.capture, meetingCapture), isTrue);

      for (var i = 0; i < 20; i++) {
        expect(
          await meeting.startScreenShare(source.id),
          isA<ScreenShareReady>(),
        );
        expect(meeting.isScreenSending, isTrue);
        await meeting.stopScreenShare();
        expect(meeting.isScreenSending, isFalse);
        expect(identical(meeting.capture, meetingCapture), isTrue);
      }

      await meeting.stop();
      expect(manager.session, isNull);

      await writeReceipt({
        'commit': hostCommit(),
        'platform': runningOnWeb ? 'web' : defaultTargetPlatform.name,
        'os': hostOs(),
        'osVersion': hostOsVersion(),
        'hardware': hostHardware(),
        'sources': [for (final item in sources) _sourceMap(item)],
        'sharedId': source.id,
        'sharedKind': source.kind.name,
        'lobbyBlocked': true,
        'includeSystemAudio': includeSound,
        'cameraPlusScreen': cameraSurface != null,
        'captureIdentityHeld': true,
        'cycles': 20,
        'skipped': false,
      });
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

String _sourceSummary(ScreenSource source) =>
    '${source.id}:${source.kind.name}:${source.width}x${source.height}';

Map<String, Object?> _sourceMap(ScreenSource source) => {
  'id': source.id,
  'name': source.name,
  'kind': source.kind.name,
  'width': source.width,
  'height': source.height,
  'canPreview': source.canPreview,
};
