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

  Future<Session> ready({
    SessionPreference preference = const SessionPreference(),
  }) async {
    final result = await manager.start(
      preference: preference,
      bargeInPolicy: BargeInPolicy.remoteVad,
    );
    return (result as StartReady).session;
  }

  test(
    'default Session is adaptive on the resolved Acoustic profile',
    () async {
      final session = await ready();
      expect(session.captureProcessor, const CaptureProcessor.adaptive());
      expect(
        session.diagnostics.acousticProfile?.family,
        AcousticFamily.communicationsHeadset,
      );
      expect(session.diagnostics.baselineStep, 4);
      expect(session.diagnostics.profileConfidence, ProfileConfidence.known);
      expect(
        session.diagnostics.captureProcessor,
        const CaptureProcessor.adaptive(),
      );
    },
  );

  test('soundFloor zero is pass-through compatibility', () async {
    final session = await ready(
      preference: const SessionPreference(soundFloor: 0),
    );
    expect(session.captureProcessor, const CaptureProcessor.passThrough());

    final frames = <Uint8List>[];
    final sub = session.capture.listen(frames.add);
    final lounge = _tone(hz: 80, amplitude: 4000);
    platform.feedCapture(lounge);
    await Future<void>.delayed(Duration.zero);
    expect(frames.single, lounge);
    await sub.cancel();
  });

  test('passThrough emits lounge rumble on the Capture stream', () async {
    final session = await ready(
      preference: const SessionPreference(
        processor: CaptureProcessor.passThrough(),
      ),
    );
    final frames = <Uint8List>[];
    final sub = session.capture.listen(frames.add);
    final lounge = _tone(hz: 80, amplitude: 4000);
    platform.feedCapture(lounge);
    await Future<void>.delayed(Duration.zero);
    expect(frames.single, lounge);
    await sub.cancel();
  });

  test('fixed high floor rejects voice without a profile multiplier', () async {
    final session = await ready(
      preference: const SessionPreference(
        processor: CaptureProcessor.fixed(0.9),
      ),
    );
    expect(session.diagnostics.activeFloor, 0.9);

    final frames = <Uint8List>[];
    final sub = session.capture.listen(frames.add);
    platform.feedCapture(_tone(hz: 700, amplitude: 8000));
    await Future<void>.delayed(Duration.zero);
    expect(frames.single, Uint8List(frames.single.length));
    expect(frames.single.every((b) => b == 0), isTrue);
    await sub.cancel();
  });

  test('profileScaled five uses the AirPods Baseline', () async {
    final session = await ready(
      preference: const SessionPreference(
        processor: CaptureProcessor.profileScaled(5),
      ),
    );
    expect(session.diagnostics.baselineStep, 4);
    expect(session.diagnostics.activeFloor, BaselinePolicy.rmsForStep(4));
  });

  test('Isolation missing raises adaptive floor only', () async {
    final session = await ready();
    platform.isolationController.add(const IsolationEvent(IsolationState.on));
    await Future<void>.delayed(Duration.zero);
    final before = session.diagnostics.activeFloor!;
    platform.isolationController.add(const IsolationEvent(IsolationState.off));
    await Future<void>.delayed(Duration.zero);
    expect(session.diagnostics.activeFloor, greaterThan(before));

    session.setCaptureProcessor(const CaptureProcessor.profileScaled(5));
    final scaled = session.diagnostics.activeFloor;
    platform.isolationController.add(const IsolationEvent(IsolationState.off));
    await Future<void>.delayed(Duration.zero);
    expect(session.diagnostics.activeFloor, scaled);
  });

  test(
    'Isolation unavailable raises floor so refuse-or-missing adapts',
    () async {
      final session = await ready();
      platform.isolationController.add(const IsolationEvent(IsolationState.on));
      await Future<void>.delayed(Duration.zero);
      final before = session.diagnostics.activeFloor!;

      // Host prompted via required; user refused / platform has no Isolation.
      platform.isolationController.add(
        const IsolationEvent(IsolationState.unavailable),
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.lastIsolation.state, IsolationState.unavailable);
      expect(session.diagnostics.activeFloor, greaterThan(before));
    },
  );

  test(
    'noiseCancelling remaps Isolation off to required and raises floor',
    () async {
      final session = await ready();
      expect(session.lastIsolation.state, IsolationState.required);
      expect(
        session.diagnostics.activeFloor,
        greaterThan(BaselinePolicy.rmsForStep(3)),
      );

      platform.isolationController.add(const IsolationEvent(IsolationState.on));
      await Future<void>.delayed(Duration.zero);
      expect(session.lastIsolation.state, IsolationState.on);

      platform.isolationController.add(
        const IsolationEvent(IsolationState.off),
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.lastIsolation.state, IsolationState.required);
    },
  );

  test('noiseCancelling off does not emit Isolation required', () async {
    final session = await ready(
      preference: const SessionPreference(noiseCancelling: false),
    );
    expect(session.lastIsolation.state, isNot(IsolationState.required));
    expect(session.lastIsolation.state, IsolationState.unavailable);

    platform.isolationController.add(const IsolationEvent(IsolationState.off));
    await Future<void>.delayed(Duration.zero);
    expect(session.lastIsolation.state, IsolationState.off);
  });

  test('Isolation streams survive openIsolationSettings', () async {
    final session = await ready();
    final isolation = session.isolation;
    final capture = session.capture;
    await session.openIsolationSettings();
    expect(identical(session.isolation, isolation), isTrue);
    expect(identical(session.capture, capture), isTrue);
    expect(platform.openIsolationSettingsCalls, 1);
  });

  test('Pair change recomputes Acoustic profile', () async {
    final session = await ready(
      preference: const SessionPreference(
        processor: CaptureProcessor.profileScaled(5),
      ),
    );
    expect(
      session.diagnostics.acousticProfile?.family,
      AcousticFamily.communicationsHeadset,
    );
    await session.select(captureId: 'speaker-in');
    expect(
      session.diagnostics.acousticProfile?.family,
      AcousticFamily.speakerphone,
    );
    expect(session.diagnostics.baselineStep, 6);
    expect(session.diagnostics.activeFloor, BaselinePolicy.rmsForStep(6));
  });
}

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
