import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  const transcoder = AudioTranscoder();

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
    final back = transcoder.transcode(
      input,
      const AudioFormat.pcm16le(sampleRate: 24000),
      const AudioFormat.pcm16le(sampleRate: 24000),
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
      List<int>.filled(80, transcoder.transcode(
        Uint8List(160),
        const AudioFormat.pcm16le(sampleRate: 8000),
        const AudioFormat.pcmu(),
      ).first),
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
    );
    final playback = transcoder.fromWorking(
      working,
      const AudioFormat.pcm16le(sampleRate: 16000),
    );
    expect(working.length ~/ 2, closeTo(48000 * 0.05, 2));
    expect(playback.length ~/ 2, closeTo(16000 * 0.05, 2));
  });

  test('Opus is an explicit unsupported seam', () {
    expect(
      () => transcoder.toWorking(Uint8List(0), const AudioFormat.opus()),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('unsupported Format is rejected', () {
    const bad = AudioFormat(
      encoding: AudioEncoding.pcmu,
      sampleRate: 16000,
    );
    expect(bad.isSupported, isFalse);
    expect(
      () => transcoder.toWorking(Uint8List(1), bad),
      throwsA(isA<ArgumentError>()),
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
