import 'dart:typed_data';

import 'audio_format.dart';

/// Converts bytes between an edge [AudioFormat] and the internal working Format
/// (PCM16 LE mono 48 kHz).
///
/// Capture and playback Formats are independent; each edge is converted on its
/// own. Linear interpolation is used for PCM resample — not a production SRC.
/// G.711 is ITU-T µ-law / A-law with documented quantization loss.
/// Opus is a typed seam: [UnsupportedError] until a codec is linked.
final class AudioTranscoder {
  /// Creates a transcoder.
  const AudioTranscoder();

  /// Internal working Format.
  static const AudioFormat working = AudioFormat.pcm16le(sampleRate: 48000);

  /// Default edge Format when the host omits one.
  static const AudioFormat defaultEdge = AudioFormat.pcm16le24k;

  /// [bytes] in [source] → working PCM16/48 kHz.
  Uint8List toWorking(Uint8List bytes, AudioFormat source) {
    _check(source);
    return switch (source.encoding) {
      AudioEncoding.pcm16le =>
        _resamplePcm16(bytes, source.sampleRate, working.sampleRate),
      AudioEncoding.pcmu => _g711ToWorking(bytes, _G711Law.muLaw),
      AudioEncoding.pcma => _g711ToWorking(bytes, _G711Law.aLaw),
      AudioEncoding.opus => throw UnsupportedError(
        'Opus is not linked. Attach an OpusCodec before using audio/opus.',
      ),
    };
  }

  /// Working PCM16/48 kHz → [target].
  Uint8List fromWorking(Uint8List bytes, AudioFormat target) {
    _check(target);
    return switch (target.encoding) {
      AudioEncoding.pcm16le =>
        _resamplePcm16(bytes, working.sampleRate, target.sampleRate),
      AudioEncoding.pcmu => _workingToG711(bytes, _G711Law.muLaw),
      AudioEncoding.pcma => _workingToG711(bytes, _G711Law.aLaw),
      AudioEncoding.opus => throw UnsupportedError(
        'Opus is not linked. Attach an OpusCodec before using audio/opus.',
      ),
    };
  }

  /// [source] → working → [target]. Capture and playback may differ.
  Uint8List transcode(
    Uint8List bytes,
    AudioFormat source,
    AudioFormat target,
  ) => fromWorking(toWorking(bytes, source), target);

  void _check(AudioFormat format) {
    if (!format.isSupported) {
      throw ArgumentError.value(format, 'format', 'unsupported Format');
    }
  }

  Uint8List _resamplePcm16(Uint8List bytes, int fromRate, int toRate) {
    if (fromRate == toRate) {
      return Uint8List.fromList(bytes);
    }
    if (bytes.length.isOdd) {
      throw ArgumentError('PCM16 byte length must be even');
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
    return _int16ToBytes(output);
  }

  Uint8List _g711ToWorking(Uint8List bytes, _G711Law law) {
    final pcm = Int16List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      pcm[i] = law == _G711Law.muLaw
          ? _muLawDecode(bytes[i])
          : _aLawDecode(bytes[i]);
    }
    return _resamplePcm16(_int16ToBytes(pcm), 8000, working.sampleRate);
  }

  Uint8List _workingToG711(Uint8List bytes, _G711Law law) {
    final pcm8k = _resamplePcm16(bytes, working.sampleRate, 8000);
    final samples = _bytesToInt16(pcm8k);
    final out = Uint8List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = law == _G711Law.muLaw
          ? _muLawEncode(samples[i])
          : _aLawEncode(samples[i]);
    }
    return out;
  }

  static const int _muLawBias = 0x84;
  static const int _muLawClip = 32635;

  int _muLawEncode(int sample) {
    var s = sample;
    final sign = s < 0 ? 0x80 : 0;
    if (s < 0) {
      s = -s;
    }
    if (s > _muLawClip) {
      s = _muLawClip;
    }
    s += _muLawBias;
    var exponent = 7;
    for (var expMask = 0x4000; (s & expMask) == 0 && exponent > 0; exponent--) {
      expMask >>= 1;
    }
    final mantissa = (s >> (exponent + 3)) & 0x0F;
    return ~(sign | (exponent << 4) | mantissa) & 0xFF;
  }

  int _muLawDecode(int muLaw) {
    final u = ~muLaw & 0xFF;
    final sign = u & 0x80;
    final exponent = (u >> 4) & 0x07;
    final mantissa = u & 0x0F;
    var sample = ((mantissa << 3) + _muLawBias) << exponent;
    sample -= _muLawBias;
    return sign != 0 ? -sample : sample;
  }

  static const int _aLawClip = 32635;

  int _aLawEncode(int sample) {
    var s = sample;
    final sign = s < 0 ? 0x80 : 0;
    if (s < 0) {
      s = -s;
    }
    if (s > _aLawClip) {
      s = _aLawClip;
    }
    var exponent = 0;
    if (s >= 256) {
      exponent = 7;
      for (var exp = 1; exp < 8; exp++) {
        if (s < (256 << exp)) {
          exponent = exp;
          break;
        }
      }
    }
    final mantissa = exponent == 0
        ? (s >> 4) & 0x0F
        : (s >> (exponent + 3)) & 0x0F;
    return (sign | (exponent << 4) | mantissa) ^ 0x55;
  }

  int _aLawDecode(int aLaw) {
    var a = aLaw ^ 0x55;
    final sign = a & 0x80;
    final exponent = (a >> 4) & 0x07;
    final mantissa = a & 0x0F;
    var sample = exponent == 0
        ? (mantissa << 4) + 8
        : ((mantissa << 4) + 0x108) << (exponent - 1);
    return sign != 0 ? -sample : sample;
  }

  Uint8List _int16ToBytes(Int16List samples) {
    final out = Uint8List(samples.length * 2);
    final data = ByteData.sublistView(out);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(i * 2, samples[i], Endian.little);
    }
    return out;
  }

  Int16List _bytesToInt16(Uint8List bytes) {
    final samples = Int16List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little);
    }
    return samples;
  }
}

enum _G711Law { muLaw, aLaw }
