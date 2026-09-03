import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_format.dart';

/// Converts bytes between an edge [AudioFormat] and the internal working Format
/// (PCM16 LE mono 48 kHz).
///
/// Capture and playback Formats are independent; each edge is converted on its
/// own with one stateful converter. PCM rate conversion is a windowed-sinc
/// resampler that keeps phase and history across chunks. G.711 is ITU-T µ-law /
/// A-law with documented quantization loss. Opus is a typed seam:
/// [UnsupportedError] until a codec is linked.
final class AudioTranscoder {
  /// Creates a transcoder. Converter state is per instance.
  AudioTranscoder();

  /// Internal working Format.
  static const AudioFormat working = AudioFormat.pcm16le(sampleRate: 48000);

  /// Default edge Format when the host omits one.
  static const AudioFormat defaultEdge = AudioFormat.pcm16le24k;

  final Map<String, _RateConverter> _converters = {};

  /// Drops converter state. Call when the Native Format on an edge changes.
  void reset() => _converters.clear();

  /// [bytes] in [source] → working PCM16/48 kHz.
  ///
  /// When [end] is true, remaining filter delay is flushed as a complete
  /// buffer. Leave [end] false for a live stream so the next chunk continues.
  Uint8List toWorking(
    Uint8List bytes,
    AudioFormat source, {
    bool end = false,
  }) => transcode(bytes, source, working, end: end);

  /// Working PCM16/48 kHz → [target].
  Uint8List fromWorking(
    Uint8List bytes,
    AudioFormat target, {
    bool end = false,
  }) => transcode(bytes, working, target, end: end);

  /// [source] → [target] with one converter on this edge.
  ///
  /// PCM-to-PCM resamples directly. G.711 is decoded or encoded at 8 kHz and
  /// resampled in one step. Pass [end] true to flush a complete buffer.
  Uint8List transcode(
    Uint8List bytes,
    AudioFormat source,
    AudioFormat target, {
    bool end = false,
  }) {
    _check(source);
    _check(target);
    if (source.encoding == AudioEncoding.opus ||
        target.encoding == AudioEncoding.opus) {
      throw UnsupportedError(
        'Opus is not linked. Attach an OpusCodec before using audio/opus.',
      );
    }
    if (source == target) {
      return Uint8List.fromList(bytes);
    }
    final sourceRate = source.encoding == AudioEncoding.pcm16le
        ? source.sampleRate
        : 8000;
    final targetRate = target.encoding == AudioEncoding.pcm16le
        ? target.sampleRate
        : 8000;
    var pcm = _decodeToPcm(bytes, source);
    if (sourceRate != targetRate) {
      pcm = _converter(sourceRate, targetRate).convert(pcm, end: end);
    }
    return _encodeFromPcm(pcm, target);
  }

  void _check(AudioFormat format) {
    if (!format.isSupported) {
      throw ArgumentError.value(format, 'format', 'unsupported Format');
    }
  }

  _RateConverter _converter(int fromRate, int toRate) {
    final key = '$fromRate:$toRate';
    return _converters.putIfAbsent(
      key,
      () => _RateConverter(fromRate: fromRate, toRate: toRate),
    );
  }

  Int16List _decodeToPcm(Uint8List bytes, AudioFormat source) {
    return switch (source.encoding) {
      AudioEncoding.pcm16le => _bytesToInt16(bytes),
      AudioEncoding.pcmu => Int16List.fromList([
        for (final b in bytes) _muLawDecode(b),
      ]),
      AudioEncoding.pcma => Int16List.fromList([
        for (final b in bytes) _aLawDecode(b),
      ]),
      AudioEncoding.opus => throw UnsupportedError(
        'Opus is not linked. Attach an OpusCodec before using audio/opus.',
      ),
    };
  }

  Uint8List _encodeFromPcm(Int16List pcm, AudioFormat target) {
    return switch (target.encoding) {
      AudioEncoding.pcm16le => _int16ToBytes(pcm),
      AudioEncoding.pcmu => Uint8List.fromList([
        for (final s in pcm) _muLawEncode(s),
      ]),
      AudioEncoding.pcma => Uint8List.fromList([
        for (final s in pcm) _aLawEncode(s),
      ]),
      AudioEncoding.opus => throw UnsupportedError(
        'Opus is not linked. Attach an OpusCodec before using audio/opus.',
      ),
    };
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
    if (bytes.length.isOdd) {
      throw ArgumentError('PCM16 byte length must be even');
    }
    final samples = Int16List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little);
    }
    return samples;
  }
}

/// Windowed-sinc resampler that keeps input history and output phase.
final class _RateConverter {
  _RateConverter({required this.fromRate, required this.toRate})
    : _cutoff = 0.45 * math.min(1.0, toRate / fromRate),
      _i0Beta = _besselI0(_beta);

  final int fromRate;
  final int toRate;
  final double _cutoff;
  final double _i0Beta;
  final List<double> _input = <double>[];
  var _inputCount = 0;
  var _dropped = 0;
  var _outputIndex = 0;

  static const int _halfTaps = 24;
  static const double _beta = 8.5;

  Int16List convert(Int16List samples, {required bool end}) {
    for (var i = 0; i < samples.length; i++) {
      _input.add(samples[i] / 32768.0);
    }
    _inputCount += samples.length;
    final expected = (_inputCount * toRate / fromRate).round();
    final step = fromRate / toRate;
    final out = <int>[];
    while (true) {
      final pos = _outputIndex * step;
      if (end) {
        if (_outputIndex >= expected) {
          break;
        }
      } else if (pos + _halfTaps > _inputCount) {
        break;
      }
      final y = _interpolate(pos).clamp(-1.0, 1.0);
      out.add((y * 32767.0).round().clamp(-32767, 32767));
      _outputIndex++;
    }
    _trim();
    return Int16List.fromList(out);
  }

  double _interpolate(double pos) {
    var acc = 0.0;
    final center = pos.round();
    final first = center - _halfTaps;
    final last = center + _halfTaps;
    for (var i = first; i <= last; i++) {
      acc += _at(i) * _kernel(pos - i);
    }
    return acc;
  }

  double _kernel(double t) {
    if (t.abs() >= _halfTaps) {
      return 0;
    }
    final x = 2 * _cutoff * t;
    final sinc = x.abs() < 1e-12 ? 1.0 : math.sin(math.pi * x) / (math.pi * x);
    final window = _kaiser(t / _halfTaps);
    return 2 * _cutoff * sinc * window;
  }

  double _kaiser(double x) {
    if (x.abs() > 1) {
      return 0;
    }
    return _besselI0(_beta * math.sqrt(1 - x * x)) / _i0Beta;
  }

  double _at(int index) {
    if (index < 0 || index >= _inputCount) {
      return 0;
    }
    final local = index - _dropped;
    if (local < 0 || local >= _input.length) {
      return 0;
    }
    return _input[local];
  }

  void _trim() {
    final keepFrom = (_outputIndex * fromRate / toRate - _halfTaps).floor();
    final drop = keepFrom - _dropped;
    if (drop <= 0 || drop > _input.length) {
      return;
    }
    _input.removeRange(0, drop);
    _dropped += drop;
  }

  static double _besselI0(double x) {
    var sum = 1.0;
    var term = 1.0;
    final y = x * x / 4;
    for (var k = 1; k < 32; k++) {
      term *= y / (k * k);
      sum += term;
      if (term < 1e-12 * sum) {
        break;
      }
    }
    return sum;
  }
}
