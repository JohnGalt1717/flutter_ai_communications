import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_ai_communications_macos/src/macos_pcm_convert.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const convert = MacPcmConvert();
  const stereo48k = AudioFormat.pcm16le(sampleRate: 48000, channels: 2);

  test('stereo 48 kHz sine is non-zero PCM16 mono 24 kHz at the edge', () {
    final native = _sine(sampleRate: 48000, channels: 2, seconds: 0.02);
    final edge = convert.toEdge(native, native: stereo48k);
    expect(edge.length, closeTo(24000 * 0.02 * 2, 4));
    expect(_rms(edge), greaterThan(0));
  });

  test('identity 24 kHz mono is unchanged', () {
    final bytes = _sine(sampleRate: 24000, channels: 1, seconds: 0.01);
    final out = convert.toEdge(bytes, native: AudioFormat.pcm16le24k);
    expect(out, bytes);
  });

  test('edge playback upmixes and resamples to stereo 48 kHz', () {
    final edge = _sine(sampleRate: 24000, channels: 1, seconds: 0.01);
    final native = convert.fromEdge(edge, native: stereo48k);
    expect(native.length, closeTo(48000 * 0.01 * 2 * 2, 8));
    expect(_rms(native), greaterThan(0));
  });
}

Uint8List _sine({
  required int sampleRate,
  required int channels,
  required double seconds,
}) {
  final frames = (sampleRate * seconds).round();
  final out = Uint8List(frames * channels * 2);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < frames; i++) {
    final sample = (sin(2 * pi * 1000 * i / sampleRate) * 0.5 * 32767).round();
    for (var ch = 0; ch < channels; ch++) {
      data.setInt16((i * channels + ch) * 2, sample, Endian.little);
    }
  }
  return out;
}

double _rms(Uint8List bytes) {
  if (bytes.length < 2) {
    return 0;
  }
  final data = ByteData.sublistView(bytes);
  final samples = bytes.length ~/ 2;
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return sqrt(sum / samples);
}
