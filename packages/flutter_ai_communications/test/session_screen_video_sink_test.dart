import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingScreenVideoSink implements ScreenVideoSink {
  final snapshots = <VideoPathSnapshot>[];

  @override
  void onScreenVideoPath(VideoPathSnapshot snapshot) {
    snapshots.add(snapshot);
  }
}

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

  test('attachScreenVideoSink sees screen send start and stop', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    final capture = session.capture;
    final sink = _RecordingScreenVideoSink();
    session.attachScreenVideoSink(sink);
    expect(sink.snapshots.single.cameraOff, isTrue);
    expect(sink.snapshots.single.generation, 0);
    expect(platform.attachedScreenProductionVideoPathTokens, hasLength(1));

    expect(
      await session.startScreenShare('display-0'),
      isA<ScreenShareReady>(),
    );
    expect(sink.snapshots.last.cameraOff, isFalse);
    expect(sink.snapshots.last.generation, 1);
    expect(sink.snapshots.last.muteVideo, isFalse);
    expect(sink.snapshots.last.processor, const NoneVideoProcessor());
    expect(sink.snapshots.last.surface?.handle, 2);
    expect(identical(session.capture, capture), isTrue);

    await session.stopScreenShare();
    expect(sink.snapshots.last.cameraOff, isTrue);
    expect(sink.snapshots.last.generation, 1);
    expect(sink.snapshots.last.surface, isNull);
    expect(session.isStopped, isFalse);
  });

  test('replace startScreenShare increments screen path generation', () async {
    final session = ((await manager.start()) as StartReady).session;
    final sink = _RecordingScreenVideoSink();
    session.attachScreenVideoSink(sink);
    await session.startScreenShare('display-0');
    await session.startScreenShare('window-notepad');
    expect(sink.snapshots.last.generation, 2);
    expect(sink.snapshots.last.cameraOff, isFalse);
  });

  test(
    'detachScreenVideoSink is idempotent and does not end the Session',
    () async {
      final session = ((await manager.start()) as StartReady).session;
      final capture = session.capture;
      final sink = _RecordingScreenVideoSink();
      session.attachScreenVideoSink(sink);
      session.detachScreenVideoSink(sink);
      session.detachScreenVideoSink(sink);
      await session.startScreenShare('display-0');
      expect(sink.snapshots, hasLength(1));
      expect(session.isStopped, isFalse);
      expect(identical(session.capture, capture), isTrue);
      expect(platform.detachedScreenProductionVideoPathTokens, hasLength(1));
    },
  );
}
