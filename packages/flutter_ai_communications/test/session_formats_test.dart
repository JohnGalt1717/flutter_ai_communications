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
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
  }) async {
    final result = await manager.start(
      captureFormat: captureFormat,
      playbackFormat: playbackFormat,
      preference: const SessionPreference(soundFloor: 0),
      bargeInPolicy: BargeInPolicy.remoteVad,
    );
    return (result as StartReady).session;
  }

  test('Opus cannot produce StartReady', () async {
    final result = await manager.start(captureFormat: const AudioFormat.opus());
    expect(result, isA<StartFailed>());
    expect(manager.session, isNull);
  });

  test('native 16 kHz capture converts to 24 kHz edge bytes', () async {
    platform.nativeCaptureFormat = const AudioFormat.pcm16le(sampleRate: 16000);
    final session = await ready();
    expect(session.diagnostics.requestedCaptureFormat, AudioFormat.pcm16le24k);
    expect(
      session.diagnostics.nativeCaptureFormat,
      const AudioFormat.pcm16le(sampleRate: 16000),
    );
    expect(session.diagnostics.edgeCaptureFormat, AudioFormat.pcm16le24k);
    expect(session.diagnostics.captureConversionPath, ConversionPath.dart);

    final frames = <Uint8List>[];
    final sub = session.capture.listen(frames.add);
    platform.feedCapture(_sinePcm(sampleRate: 16000, seconds: 0.05));
    await Future<void>.delayed(Duration.zero);

    expect(frames, hasLength(1));
    expect(frames.single.length ~/ 2, closeTo(24000 * 0.05, 48));
    expect(_rms(frames.single), greaterThan(0.1));
    expect(session.status.code, SessionStatusCode.formatConverted);
    expect(session.status.severity, StatusSeverity.warning);
    await sub.cancel();
  });

  test('playback 16 kHz edge converts to native 24 kHz', () async {
    platform.nativePlaybackFormat = AudioFormat.pcm16le24k;
    final session = await ready(
      playbackFormat: const AudioFormat.pcm16le(sampleRate: 16000),
    );
    expect(
      session.diagnostics.requestedPlaybackFormat,
      const AudioFormat.pcm16le(sampleRate: 16000),
    );
    expect(session.diagnostics.nativePlaybackFormat, AudioFormat.pcm16le24k);
    expect(session.diagnostics.playbackConversionPath, ConversionPath.dart);

    await session.play(_sinePcm(sampleRate: 16000, seconds: 0.05));
    expect(platform.played, isNotEmpty);
    expect(_joined(platform.played).length ~/ 2, closeTo(24000 * 0.05, 48));
  });

  test(
    'µ-law capture edge converts native PCM8k through the Session',
    () async {
      platform.nativeCaptureFormat = const AudioFormat.pcm16le(
        sampleRate: 8000,
      );
      final session = await ready(captureFormat: const AudioFormat.pcmu());
      expect(session.diagnostics.edgeCaptureFormat, const AudioFormat.pcmu());
      expect(session.diagnostics.captureConversionPath, ConversionPath.dart);

      final frames = <Uint8List>[];
      final sub = session.capture.listen(frames.add);
      platform.feedCapture(_sinePcm(sampleRate: 8000, seconds: 0.05));
      await Future<void>.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames.single.length, closeTo(8000 * 0.05, 48));
      expect(frames.single.every((b) => b == 0), isFalse);
      await sub.cancel();
    },
  );

  test(
    'A-law capture edge converts native PCM8k through the Session',
    () async {
      platform.nativeCaptureFormat = const AudioFormat.pcm16le(
        sampleRate: 8000,
      );
      final session = await ready(captureFormat: const AudioFormat.pcma());
      final frames = <Uint8List>[];
      final sub = session.capture.listen(frames.add);
      platform.feedCapture(_sinePcm(sampleRate: 8000, seconds: 0.05));
      await Future<void>.delayed(Duration.zero);
      expect(frames.single.length, closeTo(8000 * 0.05, 48));
      expect(frames.single.every((b) => b == 0), isFalse);
      await sub.cancel();
    },
  );

  test('matching Native Format is an identity Conversion path', () async {
    final session = await ready();
    expect(session.diagnostics.nativeCaptureFormat, AudioFormat.pcm16le24k);
    expect(session.diagnostics.captureConversionPath, ConversionPath.identity);
    expect(session.diagnostics.playbackConversionPath, ConversionPath.identity);
  });

  test('unsupported requested rate is reported and converted', () async {
    platform.unsupportedCaptureRates = {24000};
    final session = await ready();
    expect(
      session.diagnostics.nativeCaptureFormat,
      const AudioFormat.pcm16le(sampleRate: 48000),
    );
    expect(session.diagnostics.captureConversionPath, ConversionPath.dart);
    expect(session.diagnostics.formatFailures, [
      const FormatCandidateFailure(
        format: AudioFormat.pcm16le24k,
        reason: 'unsupported',
      ),
    ]);
  });

  test('Pair change renegotiates Native Formats on the same Session', () async {
    platform.catalog = [
      ...FakeCommunicationsPlatform.defaultCatalog,
      const Endpoint(
        id: 'usb-in',
        name: 'USB Audio',
        routeClass: RouteClass.wired,
        isCapture: true,
        pairId: 'usb',
      ),
      const Endpoint(
        id: 'usb-out',
        name: 'USB Audio',
        routeClass: RouteClass.wired,
        isCapture: false,
        pairId: 'usb',
      ),
    ];
    platform.nativeCaptureFormat = const AudioFormat.pcm16le(sampleRate: 16000);
    platform.nativeCaptureByEndpointId['usb-in'] = const AudioFormat.pcm16le(
      sampleRate: 48000,
    );
    final session = await ready();
    expect(
      session.diagnostics.nativeCaptureFormat,
      const AudioFormat.pcm16le(sampleRate: 16000),
    );

    await session.select(captureId: 'usb-in', renderId: 'usb-out');
    expect(
      session.diagnostics.nativeCaptureFormat,
      const AudioFormat.pcm16le(sampleRate: 48000),
    );
    expect(session.diagnostics.captureConversionPath, ConversionPath.dart);

    final frames = <Uint8List>[];
    final sub = session.capture.listen(frames.add);
    platform.feedCapture(_sinePcm(sampleRate: 48000, seconds: 0.05));
    await Future<void>.delayed(Duration.zero);
    expect(frames.single.length ~/ 2, closeTo(24000 * 0.05, 48));
    await sub.cancel();
  });
}

Uint8List _sinePcm({
  required int sampleRate,
  required double seconds,
  double hz = 700,
  int amplitude = 14000,
}) {
  final count = (sampleRate * seconds).round();
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

double _rms(Uint8List bytes) {
  if (bytes.length < 2) {
    return 0;
  }
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  final n = bytes.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return math.sqrt(sum / n);
}

Uint8List _joined(List<Uint8List> frames) {
  final out = BytesBuilder(copy: false);
  for (final frame in frames) {
    out.add(frame);
  }
  return out.toBytes();
}
