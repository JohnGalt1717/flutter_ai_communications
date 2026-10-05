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
  late CommunicationsManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = CommunicationsManager(platform: platform);
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
      preference: preference ?? const SessionPreference(soundFloor: 0.0),
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

  test(
    'Echo Transport receives capture byte for byte and plays it back',
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
    },
  );

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

  test(
    'Echo Transport does not replay host loopback capture into play',
    () async {
      final loopback = LoopbackCommunicationsPlatform(
        platform,
        includeInCatalog: true,
      );
      addTearDown(loopback.dispose);
      FlutterAiCommunicationsPlatform.instance = loopback;
      manager = CommunicationsManager(platform: loopback);
      final session = await ready();
      await session.select(
        captureId: LoopbackCommunicationsPlatform.captureId,
        renderId: LoopbackCommunicationsPlatform.renderId,
      );
      final echo = EchoTransport(session);
      await echo.attach();
      final fixture = FixturePcm.voiceBand24k();
      await session.play(fixture);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(echo.received, isNotEmpty);
      expect(platform.played, hasLength(1));
      expect(_joined(platform.played), fixture);
      await echo.dispose();
    },
  );

  test('wrapRegistered disposes the previous wrapper on catalog flag change',
      () async {
    FlutterAiCommunicationsPlatform.instance = platform;
    final first = LoopbackCommunicationsPlatform.wrapRegistered();
    expect(first.includeInCatalog, isFalse);
    final second = LoopbackCommunicationsPlatform.wrapRegistered(
      includeInCatalog: true,
    );
    expect(identical(first, second), isFalse);
    expect(second.includeInCatalog, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(first.endpointCatalog, isNot(same(second.endpointCatalog)));
    addTearDown(second.dispose);
  });

  test('host loopback Pair stays out of the Endpoint catalog', () async {
    final loopback = LoopbackCommunicationsPlatform(platform);
    addTearDown(loopback.dispose);
    final catalog = await loopback.enumerateEndpoints();
    expect(
      catalog.map((endpoint) => endpoint.id),
      isNot(contains(LoopbackCommunicationsPlatform.captureId)),
    );
    expect(
      catalog.map((endpoint) => endpoint.id),
      isNot(contains(LoopbackCommunicationsPlatform.renderId)),
    );
  });

  test('loopback Pair echoes play back on capture byte for byte', () async {
    FlutterAiCommunicationsPlatform.instance = LoopbackCommunicationsPlatform(
      platform,
      includeInCatalog: true,
    );
    manager = CommunicationsManager();
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
      includeInCatalog: true,
    );
    manager = CommunicationsManager();
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

  test('loopback startNative waits for a slow inner adapter', () async {
    platform.startNativeDelay = const Duration(milliseconds: 3500);
    final loopback = LoopbackCommunicationsPlatform(platform);
    addTearDown(loopback.dispose);
    expect(
      await loopback.startNative(
        captureId: LoopbackCommunicationsPlatform.captureId,
        renderId: LoopbackCommunicationsPlatform.renderId,
      ),
      NativeGraphStart.started,
    );
    expect(platform.startNativeCompleted, isTrue);
  });

  test(
    'loopback wrapper forwards inner Native Formats to the Session',
    () async {
      platform.nativeCaptureFormat = AudioFormat.pcm16le24k;
      platform.nativePlaybackFormat = AudioFormat.pcm16le24k;
      final loopback = LoopbackCommunicationsPlatform(platform);
      addTearDown(loopback.dispose);
      FlutterAiCommunicationsPlatform.instance = loopback;
      manager = CommunicationsManager(platform: loopback);
      const edge16k = AudioFormat.pcm16le(sampleRate: 16000);
      final result = await manager.start(
        captureFormat: edge16k,
        playbackFormat: edge16k,
        preference: const SessionPreference(soundFloor: 0.0),
      );
      final session = (result as StartReady).session;
      expect(loopback.lastNativeFormats.capture, AudioFormat.pcm16le24k);
      expect(session.diagnostics.nativeCaptureFormat, AudioFormat.pcm16le24k);
      expect(session.diagnostics.edgeCaptureFormat, edge16k);
      expect(session.diagnostics.captureConversionPath, ConversionPath.dart);
    },
  );

  test('loopback wrapper forwards screen send to the inner adapter', () async {
    final loopback = LoopbackCommunicationsPlatform(platform);
    addTearDown(loopback.dispose);
    final catalog = await loopback.enumerateScreenSources();
    expect(catalog.map((source) => source.id), contains('display-0'));
    expect(
      await loopback.startScreenShareNative(sourceId: 'display-0'),
      NativeGraphStart.started,
    );
    expect(loopback.lastScreenSurface, isNotNull);
    expect(platform.startScreenShareCalls, 1);
    await loopback.stopScreenShareNative();
  });

  test('clipped fixture is reported', () {
    final pcm = Uint8List(4);
    ByteData.sublistView(pcm)
      ..setInt16(0, 32767, Endian.little)
      ..setInt16(2, -32768, Endian.little);
    expect(PcmQuality.clipped(pcm), isTrue);
  });

  test('received buffer stays bounded after a long analog capture', () async {
    final session = await ready();
    const cap = 19200;
    final echo = EchoTransport(session, replay: false, maxReceivedBytes: cap);
    await echo.attach();
    final frame = Uint8List(480);
    for (var i = 0; i < 200; i++) {
      platform.feedCapture(frame);
    }
    await Future<void>.delayed(Duration.zero);
    expect(echo.received.length, cap);
    await echo.dispose();
  });
}

Uint8List _joined(List<Uint8List> frames) {
  final out = BytesBuilder(copy: false);
  for (final frame in frames) {
    out.add(frame);
  }
  return out.takeBytes();
}
