import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Converts PCM16 LE between a Native Format and the Session edge.
///
/// Downmix/upmix plus linear resample. One converter — the Session must
/// see [edge] bytes and must not convert again.
final class MacPcmConvert {
  /// Creates a converter.
  const MacPcmConvert();

  static const AudioFormat _edge = AudioFormat.pcm16le24k;

  /// Native capture bytes → Session-edge PCM16 LE mono 24 kHz.
  Uint8List toEdge(
    Uint8List bytes, {
    required AudioFormat native,
    AudioFormat edge = _edge,
  }) {
    if (bytes.isEmpty) {
      return bytes;
    }
    var pcm = native.channels <= 1 ? bytes : _downmix(bytes, native.channels);
    if (native.sampleRate != edge.sampleRate) {
      pcm = _resample(pcm, native.sampleRate, edge.sampleRate);
    }
    return pcm;
  }

  /// Session-edge PCM16 LE mono 24 kHz → Native playback bytes.
  Uint8List fromEdge(
    Uint8List bytes, {
    required AudioFormat native,
    AudioFormat edge = _edge,
  }) {
    if (bytes.isEmpty) {
      return bytes;
    }
    var pcm = bytes;
    if (native.sampleRate != edge.sampleRate) {
      pcm = _resample(pcm, edge.sampleRate, native.sampleRate);
    }
    if (native.channels > 1) {
      pcm = _upmix(pcm, native.channels);
    }
    return pcm;
  }

  Uint8List _downmix(Uint8List bytes, int channels) {
    final frameBytes = channels * 2;
    final frames = bytes.length ~/ frameBytes;
    if (frames == 0) {
      return Uint8List(0);
    }
    final data = ByteData.sublistView(bytes);
    final out = Uint8List(frames * 2);
    final dest = ByteData.sublistView(out);
    for (var i = 0; i < frames; i++) {
      var sum = 0;
      for (var ch = 0; ch < channels; ch++) {
        sum += data.getInt16((i * channels + ch) * 2, Endian.little);
      }
      dest.setInt16(
        i * 2,
        (sum / channels).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return out;
  }

  Uint8List _upmix(Uint8List mono, int channels) {
    final frames = mono.length ~/ 2;
    if (frames == 0) {
      return Uint8List(0);
    }
    final data = ByteData.sublistView(mono);
    final out = Uint8List(frames * channels * 2);
    final dest = ByteData.sublistView(out);
    for (var i = 0; i < frames; i++) {
      final sample = data.getInt16(i * 2, Endian.little);
      for (var ch = 0; ch < channels; ch++) {
        dest.setInt16((i * channels + ch) * 2, sample, Endian.little);
      }
    }
    return out;
  }

  Uint8List _resample(Uint8List bytes, int fromRate, int toRate) {
    if (fromRate == toRate || fromRate <= 0 || toRate <= 0) {
      return Uint8List.fromList(bytes);
    }
    if (bytes.length.isOdd) {
      return Uint8List(0);
    }
    final input = Int16List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < input.length; i++) {
      input[i] = data.getInt16(i * 2, Endian.little);
    }
    if (input.isEmpty) {
      return Uint8List(0);
    }
    final outCount = (input.length * toRate / fromRate).round().clamp(
      1,
      1 << 30,
    );
    final output = Int16List(outCount);
    for (var i = 0; i < outCount; i++) {
      final srcPos = i * fromRate / toRate;
      final index = srcPos.floor();
      final frac = srcPos - index;
      if (index + 1 < input.length) {
        output[i] = (input[index] + (input[index + 1] - input[index]) * frac)
            .round();
      } else {
        output[i] = input[index.clamp(0, input.length - 1)];
      }
    }
    final out = Uint8List(output.length * 2);
    final dest = ByteData.sublistView(out);
    for (var i = 0; i < output.length; i++) {
      dest.setInt16(i * 2, output[i], Endian.little);
    }
    return out;
  }
}
