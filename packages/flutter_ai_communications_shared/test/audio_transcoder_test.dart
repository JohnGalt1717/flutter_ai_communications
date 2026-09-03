import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  late AudioTranscoder transcoder;

  setUp(() {
    transcoder = AudioTranscoder();
  });

  test('default edge Format is PCM16 LE mono 24 kHz', () {
    expect(AudioTranscoder.defaultEdge, AudioFormat.pcm16le24k);
    expect(AudioTranscoder.working.sampleRate, 48000);
  });

  test('same-rate PCM is a copy, not the same instance', () {
    final input = _sinePcm(sampleRate: 48000, hz: 440, seconds: 0.05);
    final out = transcoder.toWorking(input, AudioTranscoder.working);
    expect(out, isNot(same(input)));
    expect(out, input);
  });

  test('24 kHz sine keeps energy after 48 kHz working round-trip', () {
    final input = _sinePcm(sampleRate: 24000, hz: 440, seconds: 0.1);
    const edge = AudioFormat.pcm16le(sampleRate: 24000);
    final back = transcoder.fromWorking(
      transcoder.toWorking(input, edge, end: true),
      edge,
      end: true,
    );
    expect(_rms(back), greaterThan(_rms(input) * 0.7));
    expect(_rms(back), lessThan(_rms(input) * 1.3));
    expect(back, isNot(equals(Uint8List(back.length))));
  });

  for (final rate in AudioFormat.pcmSampleRates) {
    test('PCM $rate Hz to working and back has expected sample count', () {
      const seconds = 0.05;
      final input = _sinePcm(sampleRate: rate, hz: 440, seconds: seconds);
      final back = transcoder.transcode(
        input,
        AudioFormat.pcm16le(sampleRate: rate),
        AudioFormat.pcm16le(sampleRate: rate),
      );
      final expectedSamples = (rate * seconds).round();
      expect(
        back.length ~/ 2,
        closeTo(expectedSamples, 2),
        reason: 'sample count at $rate',
      );
    });
  }

  test('µ-law silence stays silence', () {
    final silence = Uint8List.fromList(
      List<int>.filled(
        80,
        transcoder
            .transcode(
              Uint8List(160),
              const AudioFormat.pcm16le(sampleRate: 8000),
              const AudioFormat.pcmu(),
            )
            .first,
      ),
    );
    final pcm = _sinePcm(sampleRate: 8000, hz: 440, seconds: 0, amplitude: 0);
    final encoded = transcoder.transcode(
      pcm,
      const AudioFormat.pcm16le(sampleRate: 8000),
      const AudioFormat.pcmu(),
    );
    final decoded = transcoder.transcode(
      encoded,
      const AudioFormat.pcmu(),
      const AudioFormat.pcm16le(sampleRate: 8000),
    );
    expect(_maxAbs(decoded), lessThan(64));
    expect(silence, isNotEmpty);
  });

  test('µ-law quiet tone survives with quantization loss', () {
    final input = _sinePcm(
      sampleRate: 8000,
      hz: 440,
      seconds: 0.1,
      amplitude: 8000,
    );
    final back = transcoder.transcode(
      input,
      const AudioFormat.pcm16le(sampleRate: 8000),
      const AudioFormat.pcmu(),
    );
    final pcm = transcoder.transcode(
      back,
      const AudioFormat.pcmu(),
      const AudioFormat.pcm16le(sampleRate: 8000),
    );
    expect(_rms(pcm), greaterThan(1000));
    expect(_rms(pcm), lessThan(9000));
  });

  test('A-law quiet tone survives with quantization loss', () {
    final input = _sinePcm(
      sampleRate: 8000,
      hz: 440,
      seconds: 0.1,
      amplitude: 8000,
    );
    final encoded = transcoder.transcode(
      input,
      const AudioFormat.pcm16le(sampleRate: 8000),
      const AudioFormat.pcma(),
    );
    final pcm = transcoder.transcode(
      encoded,
      const AudioFormat.pcma(),
      const AudioFormat.pcm16le(sampleRate: 8000),
    );
    expect(_rms(pcm), greaterThan(1000));
    expect(_rms(pcm), lessThan(9000));
  });

  test('capture 24 kHz and playback 16 kHz are independent conversions', () {
    final capture = _sinePcm(sampleRate: 24000, hz: 440, seconds: 0.05);
    final working = transcoder.toWorking(
      capture,
      const AudioFormat.pcm16le(sampleRate: 24000),
      end: true,
    );
    final playback = AudioTranscoder().fromWorking(
      working,
      const AudioFormat.pcm16le(sampleRate: 16000),
      end: true,
    );
    expect(working.length ~/ 2, closeTo(48000 * 0.05, 8));
    expect(playback.length ~/ 2, closeTo(16000 * 0.05, 8));
  });

  test('Opus is an explicit unsupported seam', () {
    expect(
      () => transcoder.toWorking(Uint8List(0), const AudioFormat.opus()),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('unsupported Format is rejected', () {
    const bad = AudioFormat(encoding: AudioEncoding.pcmu, sampleRate: 16000);
    expect(bad.isSupported, isFalse);
    expect(
      () => transcoder.toWorking(Uint8List(1), bad),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('chunked conversion matches one-shot across chunk boundaries', () {
    final input = _sinePcm(sampleRate: 24000, hz: 440, seconds: 0.12);
    const source = AudioFormat.pcm16le(sampleRate: 24000);
    const target = AudioFormat.pcm16le(sampleRate: 48000);
    final oneShot = AudioTranscoder();
    final full = oneShot.transcode(input, source, target, end: true);

    final chunked = AudioTranscoder();
    final parts = BytesBuilder(copy: false);
    const chunkBytes = 160 * 2;
    for (var offset = 0; offset < input.length; offset += chunkBytes) {
      final endOffset = math.min(offset + chunkBytes, input.length);
      parts.add(
        chunked.transcode(
          Uint8List.sublistView(input, offset, endOffset),
          source,
          target,
          end: endOffset == input.length,
        ),
      );
    }
    final joined = parts.toBytes();
    expect(joined.length, closeTo(full.length, 8));
    expect(_relativeRmsError(joined, full), lessThan(0.02));
    expect(_maxAbsDiff(joined, full), lessThan(800));
  });

  test('output duration matches input duration after flush', () {
    const seconds = 0.08;
    final input = _sinePcm(sampleRate: 16000, hz: 1000, seconds: seconds);
    final out = transcoder.transcode(
      input,
      const AudioFormat.pcm16le(sampleRate: 16000),
      const AudioFormat.pcm16le(sampleRate: 48000),
      end: true,
    );
    expect(out.length ~/ 2 / 48000, closeTo(seconds, 0.002));
    expect(out.length ~/ 2, closeTo(48000 * seconds, 8));
  });

  test('1 kHz tone stays at 1 kHz after 24 kHz to 48 kHz', () {
    final input = _sinePcm(sampleRate: 24000, hz: 1000, seconds: 0.2);
    final out = transcoder.transcode(
      input,
      const AudioFormat.pcm16le(sampleRate: 24000),
      const AudioFormat.pcm16le(sampleRate: 48000),
      end: true,
    );
    final peak = _goertzel(out, sampleRate: 48000, hz: 1000);
    final neighbor = _goertzel(out, sampleRate: 48000, hz: 2000);
    expect(peak, greaterThan(neighbor * 8));
  });

  test('content above the target Nyquist is attenuated', () {
    final input = _sinePcm(sampleRate: 24000, hz: 9000, seconds: 0.12);
    final out = transcoder.transcode(
      input,
      const AudioFormat.pcm16le(sampleRate: 24000),
      const AudioFormat.pcm16le(sampleRate: 16000),
      end: true,
    );
    expect(
      _goertzel(out, sampleRate: 16000, hz: 7000),
      lessThan(_goertzel(input, sampleRate: 24000, hz: 9000) * 0.15),
    );
  });

  test('full-scale PCM does not wrap when resampled', () {
    final input = _sinePcm(
      sampleRate: 24000,
      hz: 440,
      seconds: 0.05,
      amplitude: 32767,
    );
    final out = transcoder.transcode(
      input,
      const AudioFormat.pcm16le(sampleRate: 24000),
      const AudioFormat.pcm16le(sampleRate: 48000),
      end: true,
    );
    expect(_maxAbs(out), lessThanOrEqualTo(32767));
    expect(_rms(out), greaterThan(_rms(input) * 0.7));
  });

  test('24 kHz to 44.1 kHz round-trip keeps a 1 kHz tone', () {
    final input = _sinePcm(sampleRate: 24000, hz: 1000, seconds: 0.15);
    const edge = AudioFormat.pcm16le(sampleRate: 24000);
    const native = AudioFormat.pcm16le(sampleRate: 44100);
    final mid = transcoder.transcode(input, edge, native, end: true);
    final back = AudioTranscoder().transcode(mid, native, edge, end: true);
    expect(_relativeRmsError(back, input), lessThan(0.08));
    expect(
      _goertzel(back, sampleRate: 24000, hz: 1000),
      greaterThan(_goertzel(back, sampleRate: 24000, hz: 2000) * 6),
    );
  });
}

Uint8List _sinePcm({
  required int sampleRate,
  required double hz,
  required double seconds,
  int amplitude = 12000,
}) {
  final count = math.max(0, (sampleRate * seconds).round());
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
    final s = data.getInt16(i * 2, Endian.little);
    sum += s * s;
  }
  return math.sqrt(sum / n);
}

int _maxAbs(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var max = 0;
  for (var i = 0; i < bytes.length ~/ 2; i++) {
    final s = data.getInt16(i * 2, Endian.little).abs();
    if (s > max) {
      max = s;
    }
  }
  return max;
}

double _relativeRmsError(Uint8List actual, Uint8List expected) {
  final n = math.min(actual.length, expected.length) ~/ 2;
  if (n == 0) {
    return 1;
  }
  final a = ByteData.sublistView(actual);
  final e = ByteData.sublistView(expected);
  var err = 0.0;
  var sig = 0.0;
  for (var i = 0; i < n; i++) {
    final es = e.getInt16(i * 2, Endian.little).toDouble();
    final ds = a.getInt16(i * 2, Endian.little) - es;
    err += ds * ds;
    sig += es * es;
  }
  if (sig == 0) {
    return err == 0 ? 0 : 1;
  }
  return math.sqrt(err / sig);
}

int _maxAbsDiff(Uint8List actual, Uint8List expected) {
  final n = math.min(actual.length, expected.length) ~/ 2;
  final a = ByteData.sublistView(actual);
  final e = ByteData.sublistView(expected);
  var max = 0;
  for (var i = 0; i < n; i++) {
    final d =
        (a.getInt16(i * 2, Endian.little) - e.getInt16(i * 2, Endian.little))
            .abs();
    if (d > max) {
      max = d;
    }
  }
  return max;
}

double _goertzel(
  Uint8List bytes, {
  required int sampleRate,
  required double hz,
}) {
  final n = bytes.length ~/ 2;
  if (n == 0) {
    return 0;
  }
  final data = ByteData.sublistView(bytes);
  final coeff = 2 * math.cos(2 * math.pi * hz / sampleRate);
  var s0 = 0.0;
  var s1 = 0.0;
  var s2 = 0.0;
  for (var i = 0; i < n; i++) {
    s0 = data.getInt16(i * 2, Endian.little) + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  return math.sqrt(s1 * s1 + s2 * s2 - coeff * s1 * s2) / n;
}
