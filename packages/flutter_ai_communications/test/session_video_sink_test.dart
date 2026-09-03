import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingVideoSink implements VideoSink {
  final snapshots = <VideoPathSnapshot>[];
  void Function(VideoPathSnapshot snapshot)? onNotify;

  @override
  void onVideoPath(VideoPathSnapshot snapshot) {
    snapshots.add(snapshot);
    onNotify?.call(snapshot);
  }
}

/// Overrides == so a Set/Map that is not identity-based would collapse them.
final class _EqualVideoSink implements VideoSink {
  final snapshots = <VideoPathSnapshot>[];

  @override
  void onVideoPath(VideoPathSnapshot snapshot) => snapshots.add(snapshot);

  @override
  bool operator ==(Object other) => other is _EqualVideoSink;

  @override
  int get hashCode => 0;
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
    await manager.cameraPreview?.stop();
    await manager.session?.stop();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('two Video sinks attach at once and see the same path', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    final capture = session.capture;
    final first = _RecordingVideoSink();
    final second = _RecordingVideoSink();

    session.attachVideoSink(first);
    session.attachVideoSink(second);

    expect(first.snapshots, hasLength(1));
    expect(second.snapshots, hasLength(1));
    expect(first.snapshots.single, second.snapshots.single);
    expect(first.snapshots.single.generation, 1);
    expect(first.snapshots.single.muteVideo, isFalse);
    expect(first.snapshots.single.cameraOff, isFalse);
    expect(first.snapshots.single.processor, const NoneVideoProcessor());
    expect(first.snapshots.single.surface?.handle, 1);
    expect(identical(session.capture, capture), isTrue);
    expect(platform.attachedProductionVideoPathTokens, hasLength(2));
  });

  test('Mute-video and Camera-off notify Video sinks differently', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    final first = _RecordingVideoSink();
    final second = _RecordingVideoSink();
    session.attachVideoSink(first);
    session.attachVideoSink(second);

    await session.muteVideo();
    expect(first.snapshots.last.muteVideo, isTrue);
    expect(first.snapshots.last.cameraOff, isFalse);
    expect(first.snapshots.last.surface, isNotNull);
    expect(first.snapshots.last.generation, 1);
    expect(second.snapshots.last, first.snapshots.last);

    await session.setCameraEnabled(false);
    expect(first.snapshots.last.muteVideo, isFalse);
    expect(first.snapshots.last.cameraOff, isTrue);
    expect(first.snapshots.last.surface, isNull);
    expect(first.snapshots.last.generation, 1);
    expect(second.snapshots.last, first.snapshots.last);
    expect(session.isStopped, isFalse);
  });

  test(
    'detach is idempotent and does not end the Session or Capture stream',
    () async {
      final session =
          ((await manager.start(cameraSend: true)) as StartReady).session;
      final capture = session.capture;
      final sink = _RecordingVideoSink();
      session.attachVideoSink(sink);
      expect(sink.snapshots, hasLength(1));

      session.detachVideoSink(sink);
      session.detachVideoSink(sink);
      await session.muteVideo();

      expect(sink.snapshots, hasLength(1));
      expect(session.isStopped, isFalse);
      expect(identical(session.capture, capture), isTrue);
      expect(platform.detachedProductionVideoPathTokens, hasLength(1));
    },
  );

  test(
    'enableVideo later notifies attached Video sinks on the same Capture stream',
    () async {
      final session = ((await manager.start()) as StartReady).session;
      final capture = session.capture;
      final sink = _RecordingVideoSink();
      session.attachVideoSink(sink);
      expect(sink.snapshots.single.cameraOff, isTrue);
      expect(sink.snapshots.single.generation, 0);

      await session.enableVideo();
      expect(identical(session.capture, capture), isTrue);
      expect(sink.snapshots.last.cameraOff, isFalse);
      expect(sink.snapshots.last.generation, 1);
      expect(sink.snapshots.last.surface, isNotNull);
    },
  );

  test('Video sinks are tracked by identity when they override ==', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    final first = _EqualVideoSink();
    final second = _EqualVideoSink();
    session.attachVideoSink(first);
    session.attachVideoSink(second);
    expect(platform.attachedProductionVideoPathTokens, hasLength(2));
    session.detachVideoSink(first);
    await session.muteVideo();
    expect(first.snapshots, hasLength(1));
    expect(second.snapshots.last.muteVideo, isTrue);
  });

  test('onVideoPath may detach during notify', () async {
    final session =
        ((await manager.start(cameraSend: true)) as StartReady).session;
    final first = _RecordingVideoSink();
    final second = _RecordingVideoSink();
    first.onNotify = (_) => session.detachVideoSink(first);
    session.attachVideoSink(first);
    session.attachVideoSink(second);
    await session.muteVideo();
    expect(second.snapshots.last.muteVideo, isTrue);
    expect(session.isStopped, isFalse);
  });
}
