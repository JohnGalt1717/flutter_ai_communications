import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeCommunicationsPlatform platform;
  late DefaultCoverageSource coverage;
  late AudioManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    Session.stallTimeout = const Duration(seconds: 2);
    Session.teardownTimeout = const Duration(seconds: 2);
    platform = FakeCommunicationsPlatform();
    coverage = DefaultCoverageSource();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = AudioManager(platform: platform, coverageSource: coverage);
  });

  tearDown(() async {
    Session.stallTimeout = const Duration(seconds: 2);
    Session.teardownTimeout = const Duration(seconds: 2);
    await manager.session?.stop();
    await coverage.dispose();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  Future<Session> ready({String? purpose}) async {
    final result = await manager.start(purpose: purpose);
    return (result as StartReady).session;
  }

  group('serialized lifecycle', () {
    test('user pause is not resumed by Coverage restoration', () async {
      final session = await ready();
      await session.pause();
      expect(session.isPaused, isTrue);

      coverage.report(const Coverage.lost(reason: CoverageReason.hostReported));
      await _microtask();
      expect(session.isPaused, isTrue);

      coverage.report(const Coverage.ok());
      await _microtask();
      expect(session.isPaused, isTrue);
      expect(identical(manager.session, session), isTrue);
    });

    test(
      'interruption end auto-resumes only when interruption parked',
      () async {
        final session = await ready();
        platform.audioFocusController.add(AudioFocusState.interrupted);
        await _microtask();
        expect(session.isPaused, isTrue);
        expect(session.status.code, SessionStatusCode.interrupted);

        platform.audioFocusController.add(AudioFocusState.active);
        await _microtask();
        expect(session.isPaused, isFalse);
        expect(identical(manager.session, session), isTrue);
      },
    );

    test('interruption end does not resume a user-paused Session', () async {
      final session = await ready();
      await session.pause();
      platform.audioFocusController.add(AudioFocusState.interrupted);
      await _microtask();
      platform.audioFocusController.add(AudioFocusState.active);
      await _microtask();
      expect(session.isPaused, isTrue);
    });

    test('stop releases ownership when native teardown faults', () async {
      platform.stopNativeError = StateError('teardown');
      final session = await ready();
      await session.stop();
      expect(session.isStopped, isTrue);
      expect(manager.session, isNull);
      expect(await manager.start(), isA<StartReady>());
    });

    test(
      'start waits for in-flight teardown then creates a new Session',
      () async {
        platform.stopNativeGate = Completer<void>();
        final first = await ready(purpose: 'scribe');
        final stopping = first.stop();
        expect(first.isStopping, isTrue);

        final started = manager.start(purpose: 'review');
        platform.stopNativeGate!.complete();
        await stopping;
        final result = await started;
        expect(result, isA<StartReady>());
        final second = (result as StartReady).session;
        expect(second.purpose, 'review');
        expect(identical(second, first), isFalse);
      },
    );

    test('concurrent start while live is alreadyActive', () async {
      await ready(purpose: 'scribe');
      final second = await manager.start(purpose: 'review');
      expect(second, isA<StartAlreadyActive>());
      expect((second as StartAlreadyActive).purpose, 'scribe');
    });

    test('select then stop leaves no live Session', () async {
      final session = await ready();
      await Future.wait([
        session.select(captureId: 'handset-in'),
        session.stop(),
      ]);
      expect(session.isStopped, isTrue);
      expect(manager.session, isNull);
    });

    test('repeated start and stop do not leak native graphs', () async {
      for (var i = 0; i < 5; i++) {
        final session = await ready();
        platform.feedCapture(_voiceFrame());
        await _microtask();
        await session.stop();
        expect(manager.session, isNull);
      }
      expect(platform.startNativeCalls, 5);
      expect(platform.nativeRunning, isFalse);
    });

    test(
      'stale route events from a prior graph generation are ignored',
      () async {
        Session.stallTimeout = const Duration(milliseconds: 20);
        final session = await ready();
        platform.feedCapture(_voiceFrame());
        await _microtask();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(platform.resetNativeCalls, greaterThan(0));
        final observed = session.diagnostics.observed.captureId;

        platform.osRouteController.add(
          const OsRouteChange(
            captureId: 'handset-in',
            renderId: 'handset-out',
            generation: 1,
          ),
        );
        await _microtask();
        expect(session.diagnostics.observed.captureId, observed);
        expect(session.diagnostics.observed.captureId, isNot('handset-in'));
      },
    );

    test(
      'capture stall resets under the same Session and Capture stream',
      () async {
        Session.stallTimeout = const Duration(milliseconds: 20);
        final session = await ready();
        final capture = session.capture;
        platform.feedCapture(_voiceFrame());
        await _microtask();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(session.status.code, SessionStatusCode.captureStalled);
        expect(session.status.severity, StatusSeverity.warning);
        expect(identical(session.capture, capture), isTrue);
        expect(identical(manager.session, session), isTrue);
        expect(platform.resetNativeCalls, greaterThan(0));

        platform.feedCapture(_voiceFrame());
        await _microtask();
        expect(session.status.code, SessionStatusCode.ready);
        expect(identical(session.capture, capture), isTrue);
      },
    );

    test('stop completes on a fake clock with AlwaysOk Coverage', () {
      fakeAsync((async) {
        late Session session;
        final okManager = AudioManager(
          platform: platform,
          coverageSource: const AlwaysOkCoverageSource(),
        );
        okManager.start().then((result) {
          session = (result as StartReady).session;
        });
        async.flushMicrotasks();
        var stopped = false;
        session.stop().then((_) => stopped = true);
        async.flushMicrotasks();
        expect(stopped, isTrue);
        expect(session.isStopped, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });
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
