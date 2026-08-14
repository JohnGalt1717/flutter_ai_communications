import 'dart:typed_data';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/echo/echo_transport.dart';
import 'package:flutter_ai_communications_example/echo/fixture_pcm.dart';
import 'package:flutter_ai_communications_example/echo/loopback_platform.dart';
import 'package:flutter_ai_communications_example/echo/loopback_probe.dart';
import 'package:flutter_ai_communications_example/echo/pcm_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeCommunicationsPlatform platform;
  late AudioManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = AudioManager(platform: platform);
  });

  tearDown(() async {
    await manager.session?.stop();
    final instance = FlutterAiCommunicationsPlatform.isRegistered
        ? FlutterAiCommunicationsPlatform.instance
        : null;
    if (instance is LoopbackCommunicationsPlatform) {
      await instance.dispose();
    }
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  Future<Session> ready({SessionPreference? preference}) async {
    final result = await manager.start(
      preference:
          preference ??
          const SessionPreference(soundFloor: 0.0),
      bargeInPolicy: BargeInPolicy.remoteVad,
    );
    return (result as StartReady).session;
  }

  test('fixture WAV round-trips as PCM16 LE mono 24 kHz', () {
    final pcm = FixturePcm.voiceBand24k();
    final wav = FixturePcm.toWav(pcm, sampleRate: 24000);
    final parsed = FixturePcm.readWav(wav);
    expect(parsed, pcm);
    expect(PcmQuality.clipped(pcm), isFalse);
    expect(PcmQuality.peak(pcm), lessThan(32767));
  });

  test('Echo Transport receives capture byte for byte and plays it back',
      () async {
    final session = await ready();
    final echo = EchoTransport(session);
    await echo.attach();
    final fixture = FixturePcm.voiceBand24k();

    platform.feedCapture(fixture);
    await Future<void>.delayed(Duration.zero);

    expect(echo.received, fixture);
    expect(platform.played, isNotEmpty);
    expect(_joined(platform.played), fixture);
    expect(PcmQuality.clipped(echo.received), isFalse);
    await echo.dispose();
  });

  test('select then stream again is still byte-identical', () async {
    final session = await ready();
    final echo = EchoTransport(session);
    await echo.attach();

    platform.feedCapture(FixturePcm.voiceBand24k());
    await Future<void>.delayed(Duration.zero);
    expect(echo.received, FixturePcm.voiceBand24k());

    echo.beginLeg();
    await session.select(captureId: 'airpods-in');
    expect(session.selectedCaptureId, 'airpods-in');
    expect(session.selectedRenderId, 'airpods-out');

    final second = FixturePcm.voiceBand24k(phase: 1);
    platform.feedCapture(second);
    await Future<void>.delayed(Duration.zero);

    expect(echo.received, second);
    expect(PcmQuality.clipped(echo.received), isFalse);
    expect(_joined(platform.played), isNot(equals(Uint8List(0))));
    await echo.dispose();
  });

  test('replay off records capture and does not play it back', () async {
    final session = await ready();
    final echo = EchoTransport(session, replay: false);
    await echo.attach();
    final fixture = FixturePcm.voiceBand24k();
    platform.feedCapture(fixture);
    await Future<void>.delayed(Duration.zero);
    expect(echo.received, fixture);
    expect(platform.played, isEmpty);
    await echo.dispose();
  });

  test('loopback Pair echoes play back on capture byte for byte', () async {
    FlutterAiCommunicationsPlatform.instance = LoopbackCommunicationsPlatform(
      platform,
    );
    manager = AudioManager();
    final session = await ready(
      preference: const SessionPreference(
        captureId: LoopbackCommunicationsPlatform.captureId,
        renderId: LoopbackCommunicationsPlatform.renderId,
        soundFloor: 0,
      ),
    );
    expect(session.selectedCaptureId, LoopbackCommunicationsPlatform.captureId);
    final fixture = FixturePcm.voiceBand24k();
    final seen = <Uint8List>[];
    final sub = session.capture.listen(seen.add);
    await session.play(fixture);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    final received = _joined(seen);
    expect(platform.played, isNotEmpty);
    expect(_joined(platform.played), fixture);
    expect(received, fixture);
  });

  test('loopback still matches after selecting another Endpoint', () async {
    FlutterAiCommunicationsPlatform.instance = LoopbackCommunicationsPlatform(
      platform,
    );
    manager = AudioManager();
    final session = await ready(
      preference: const SessionPreference(
        captureId: LoopbackCommunicationsPlatform.captureId,
        renderId: LoopbackCommunicationsPlatform.renderId,
        soundFloor: 0,
      ),
    );
    final probe = const LoopbackProbe();
    final first = FixturePcm.voiceBand24k();
    final firstProof = await probe.echo(
      session: session,
      fixture: first,
      captureBefore: session.capture,
    );
    expect(firstProof.identical, isTrue);
    expect(firstProof.sameCaptureStream, isTrue);

    await session.select(captureId: 'airpods-in');
    expect(session.selectedCaptureId, 'airpods-in');

    final second = FixturePcm.voiceBand24k(phase: 1);
    final secondProof = await probe.echo(
      session: session,
      fixture: second,
      captureBefore: session.capture,
    );
    expect(secondProof.identical, isTrue);
    expect(secondProof.sameCaptureStream, isTrue);
    expect(secondProof.captureId, LoopbackCommunicationsPlatform.captureId);
  });

  test('LoopbackProbe digital identity uses the committed WAV', () async {
    final session = await ready();
    final probe = const LoopbackProbe();
    final fixture = FixturePcm.voiceBand24k();
    final proof = await probe.digital(
      session: session,
      inject: platform.feedCapture,
      fixture: fixture,
      captureBefore: session.capture,
    );
    expect(proof.identical, isTrue);
    expect(proof.clipped, isFalse);
    expect(proof.sameCaptureStream, isTrue);
    expect(proof.bytes, fixture.length);
  });

  test('clipped fixture is reported', () {
    final pcm = Uint8List(4);
    ByteData.sublistView(pcm)
      ..setInt16(0, 32767, Endian.little)
      ..setInt16(2, -32768, Endian.little);
    expect(PcmQuality.clipped(pcm), isTrue);
  });
}

Uint8List _joined(List<Uint8List> frames) {
  final out = BytesBuilder(copy: false);
  for (final frame in frames) {
    out.add(frame);
  }
  return out.takeBytes();
}
