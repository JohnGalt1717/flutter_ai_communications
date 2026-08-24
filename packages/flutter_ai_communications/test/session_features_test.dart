import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeCommunicationsPlatform platform;
  late DefaultCoverageSource coverage;
  late AudioManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    platform = FakeCommunicationsPlatform();
    coverage = DefaultCoverageSource();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = AudioManager(platform: platform, coverageSource: coverage);
  });

  tearDown(() async {
    await manager.session?.stop();
    await coverage.dispose();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  Future<Session> ready() async {
    final result = await manager.start();
    return (result as StartReady).session;
  }

  group('pairing', () {
    test('AirPods-in follows render on the live Session', () async {
      final session = await ready();
      await session.select(captureId: 'airpods-in');
      expect(session.selectedCaptureId, 'airpods-in');
      expect(session.selectedRenderId, 'airpods-out');
      expect(platform.selectedCaptureId, 'airpods-in');
      expect(platform.selectedRenderId, 'airpods-out');
    });

    test('AirPods-out falls back to speakerphone', () async {
      final session = await ready();
      await session.select(captureId: 'airpods-in');
      platform.publishCatalog(
        platform.catalog.where((e) => e.pairId != 'airpods').toList(),
      );
      await _microtask();
      expect(session.selectedCaptureId, 'speaker-in');
      expect(session.selectedRenderId, 'speaker-out');
    });

    test(
      'OS-forced route updates Observed without rewriting Desired',
      () async {
        final session = await ready();
        await session.select(captureId: 'airpods-in', renderId: 'speaker-out');
        expect(session.pairing.renderOverride, isTrue);
        platform.osRouteController.add(
          const OsRouteChange(captureId: 'airpods-in', renderId: 'airpods-out'),
        );
        await _microtask();
        expect(session.diagnostics.desired.renderId, 'speaker-out');
        expect(session.diagnostics.observed.renderId, 'airpods-out');
        expect(session.pairing.renderOverride, isTrue);
      },
    );
  });

  group('barge-in', () {
    test('voice during playback flushes play and keeps preroll', () async {
      final session = await ready();
      await session.play(Uint8List.fromList([1, 2, 3, 4]));
      expect(platform.played, isNotEmpty);

      platform.feedCapture(_tone(hz: 80, amplitude: 800));
      await _microtask();
      platform.feedCapture(_tone(hz: 700, amplitude: 14000));
      await _microtask();

      expect(platform.flushPlaybackCalls, 1);
      expect(platform.played, isEmpty);
    });

    test('play queues without marking rendered; flush zeros queued', () async {
      final session = await ready();
      await session.play(Uint8List(2400));
      expect(session.diagnostics.playbackAccepted, 1);
      expect(session.diagnostics.playbackQueued, 1);
      expect(session.diagnostics.playbackRendered, 0);

      platform.feedCapture(_tone(hz: 80, amplitude: 800));
      await _microtask();
      platform.feedCapture(_tone(hz: 700, amplitude: 14000));
      await _microtask();

      expect(session.diagnostics.playbackQueued, 0);
      expect(session.diagnostics.playbackFlushed, 1);
      expect(platform.flushPlaybackCalls, 1);
    });

    test('remoteVad does not flush playback', () async {
      final result = await manager.start(
        bargeInPolicy: BargeInPolicy.remoteVad,
      );
      final session = (result as StartReady).session;
      await session.play(Uint8List.fromList([1, 2, 3, 4]));
      platform.feedCapture(_tone(hz: 700, amplitude: 14000));
      await _microtask();
      expect(platform.flushPlaybackCalls, 0);
      expect(platform.played, isNotEmpty);
    });
  });

  group('coverage', () {
    test('host lost parks; ok resumes the same Session', () async {
      final session = await ready();
      coverage.report(const Coverage.lost(reason: CoverageReason.hostReported));
      await _microtask();
      expect(session.isPaused, isTrue);

      coverage.report(const Coverage.ok());
      await _microtask();
      expect(session.isPaused, isFalse);
      expect(identical(manager.session, session), isTrue);
    });

    test('path death is pathDead and parks', () async {
      final session = await ready();
      final seen = <Coverage>[];
      final sub = session.coverage.listen(seen.add);
      platform.pathCoverageController.add(const CoverageHint.dead());
      await _microtask();
      expect(session.isPaused, isTrue);
      expect(
        seen.any(
          (c) =>
              c.level == CoverageLevel.lost &&
              c.reason == CoverageReason.pathDead,
        ),
        isTrue,
      );
      await sub.cancel();
    });

    test('audio-focus interruption auto-pauses and is resumable', () async {
      final session = await ready();
      platform.audioFocusController.add(AudioFocusState.interrupted);
      await _microtask();
      expect(session.isPaused, isTrue);
      await session.resume();
      expect(session.isPaused, isFalse);
      expect(identical(manager.session, session), isTrue);
    });
  });
}

Future<void> _microtask() => Future<void>.delayed(Duration.zero);

Uint8List _tone({required double hz, required int amplitude}) {
  const sampleRate = 24000;
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
