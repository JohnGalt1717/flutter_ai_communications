import 'dart:math' as math;
import 'dart:typed_data';

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

  group('start results', () {
    test('granted native start is ready with a Session', () async {
      final result = await manager.start();
      expect(result, isA<StartReady>());
      final session = (result as StartReady).session;
      expect(identical(manager.session, session), isTrue);
      expect(session.captureFormat, AudioFormat.pcm16le24k);
      expect(session.playbackFormat, AudioFormat.pcm16le24k);
    });

    test('denied microphone is StartDenied', () async {
      platform.permission = MicrophonePermission.denied;
      expect(await manager.start(), isA<StartDenied>());
      expect(manager.session, isNull);
    });

    test('restricted microphone is StartRestricted', () async {
      platform.permission = MicrophonePermission.restricted;
      expect(await manager.start(), isA<StartRestricted>());
      expect(manager.session, isNull);
    });

    test('native unavailable is StartUnavailable', () async {
      platform.nativeStart = NativeGraphStart.unavailable;
      expect(await manager.start(), isA<StartUnavailable>());
      expect(manager.session, isNull);
    });

    test('native failed is StartFailed', () async {
      platform.nativeStart = NativeGraphStart.failed;
      expect(await manager.start(), isA<StartFailed>());
      expect(manager.session, isNull);
    });

    test('native throw is StartFailed with cause', () async {
      platform.startNativeError = StateError('graph');
      final result = await manager.start();
      expect(result, isA<StartFailed>());
      expect((result as StartFailed).cause, isA<StateError>());
    });

    test('second start is alreadyActive', () async {
      expect(await manager.start(), isA<StartReady>());
      expect(await manager.start(), isA<StartAlreadyActive>());
    });

    test('unsupported Format is StartFailed', () async {
      const bad = AudioFormat(encoding: AudioEncoding.pcmu, sampleRate: 16000);
      expect(await manager.start(captureFormat: bad), isA<StartFailed>());
    });
  });

  test('idle catalog lists handset and speakerphone', () async {
    final catalog = await manager.endpoints();
    expect(catalog.any((e) => e.routeClass == RouteClass.handset), isTrue);
    expect(catalog.any((e) => e.routeClass == RouteClass.speakerphone), isTrue);
    expect(manager.session, isNull);
  });

  test('one live Session; stop clears it so start can run again', () async {
    final first = await manager.start();
    final session = (first as StartReady).session;
    await session.stop();
    expect(manager.session, isNull);
    expect(session.isStopped, isTrue);
    final second = await manager.start();
    expect(second, isA<StartReady>());
    expect(identical((second as StartReady).session, session), isFalse);
  });

  test('muted Session still emits silence frames on the same capture subscription',
      () async {
    final session = ((await manager.start()) as StartReady).session;
    final frames = <Uint8List>[];
    final sub = session.capture.listen(frames.add);
    final voice = _voiceFrame();

    platform.feedCapture(voice);
    await _microtask();
    expect(frames, [voice]);

    session.mute();
    platform.feedCapture(voice);
    await _microtask();
    expect(frames, hasLength(2));
    expect(frames.last, Uint8List(voice.length));
    expect(frames.last, isNot(equals(voice)));

    await sub.cancel();
  });

  test('pause then resume keeps the Session and its capture stream', () async {
    final session = ((await manager.start()) as StartReady).session;
    final capture = session.capture;
    final frames = <Uint8List>[];
    final sub = capture.listen(frames.add);
    final voice = _voiceFrame();

    await session.pause();
    expect(session.isPaused, isTrue);
    platform.feedCapture(voice);
    await _microtask();
    expect(frames, isEmpty);

    await session.resume();
    expect(identical(manager.session, session), isTrue);
    expect(identical(session.capture, capture), isTrue);
    expect(session.isPaused, isFalse);

    platform.feedCapture(voice);
    await _microtask();
    expect(frames, [voice]);
    await sub.cancel();
  });

  test('ephemeral select and floor do not rewrite start preference', () async {
    const preference = SessionPreference(
      captureId: 'handset-in',
      renderId: 'handset-out',
      soundFloor: 0.1,
    );
    final session =
        ((await manager.start(preference: preference)) as StartReady).session;

    await session.select(captureId: 'speaker-in', renderId: 'speaker-out');
    session.setSoundFloor(0.5);

    expect(session.preference.captureId, 'handset-in');
    expect(session.preference.renderId, 'handset-out');
    expect(session.preference.soundFloor, 0.1);
    expect(session.selectedCaptureId, 'speaker-in');
    expect(session.selectedRenderId, 'speaker-out');
    expect(session.soundFloor, 0.5);
    expect(platform.selectedCaptureId, 'speaker-in');
  });

  test('capture and playback Formats may differ', () async {
    final session =
        ((await manager.start(
              captureFormat: const AudioFormat.pcm16le(sampleRate: 24000),
              playbackFormat: const AudioFormat.pcm16le(sampleRate: 16000),
            ))
            as StartReady)
            .session;
    expect(session.captureFormat.sampleRate, 24000);
    expect(session.playbackFormat.sampleRate, 16000);
  });

  test('play is a no-op while paused', () async {
    final session = ((await manager.start()) as StartReady).session;
    await session.pause();
    await session.play(Uint8List.fromList([1, 2]));
    expect(platform.played, isEmpty);
  });
}

Future<void> _microtask() => Future<void>.delayed(Duration.zero);

Uint8List _voiceFrame() {
  const sampleRate = 24000;
  const hz = 700.0;
  const amplitude = 14000;
  final count = (sampleRate * 0.05).round();
  final out = Uint8List(count * 2);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < count; i++) {
    final sample = (math.sin(2 * math.pi * hz * i / sampleRate) * amplitude)
        .round()
        .clamp(-32767, 32767);
    data.setInt16(i * 2, sample, Endian.little);
  }
  return out;
}
