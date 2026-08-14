import 'dart:math' as math;
import 'dart:typed_data';

/// Known-good PCM16 LE mono fixtures and WAV wrap/unwrap.
///
/// Default edge Format is 24 kHz. Amplitude stays below full scale so
/// clipping is a defect, not a fixture property.
final class FixturePcm {
  /// Voice-band tone that passes the Session sound floor.
  static Uint8List voiceBand24k({
    int sampleRate = 24000,
    double seconds = 0.2,
    double phase = 0,
  }) {
    final count = (sampleRate * seconds).round();
    final out = Uint8List(count * 2);
    final data = ByteData.sublistView(out);
    const amplitude = 12000.0;
    for (var i = 0; i < count; i++) {
      final t = (i / sampleRate) + phase * 0.001;
      final sample =
          (math.sin(2 * math.pi * 700 * t) * 0.7 +
              math.sin(2 * math.pi * 1100 * t) * 0.3) *
          amplitude;
      data.setInt16(i * 2, sample.round().clamp(-32767, 32767), Endian.little);
    }
    return out;
  }

  /// Wraps PCM16 LE mono as a WAV file.
  static Uint8List toWav(Uint8List pcm, {required int sampleRate}) {
    final header = ByteData(44);
    final byteRate = sampleRate * 2;
    header
      ..setUint32(0, 0x52494646, Endian.big) // RIFF
      ..setUint32(4, 36 + pcm.length, Endian.little)
      ..setUint32(8, 0x57415645, Endian.big) // WAVE
      ..setUint32(12, 0x666d7420, Endian.big) // fmt
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, byteRate, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461, Endian.big) // data
      ..setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
  }

  /// Reads PCM16 LE mono from a WAV file.
  static Uint8List readWav(Uint8List wav) {
    if (wav.length < 44) {
      throw const FormatException('WAV too short');
    }
    final data = ByteData.sublistView(wav);
    if (data.getUint32(0, Endian.big) != 0x52494646 ||
        data.getUint32(8, Endian.big) != 0x57415645) {
      throw const FormatException('not RIFF WAVE');
    }
    var offset = 12;
    while (offset + 8 <= wav.length) {
      final id = data.getUint32(offset, Endian.big);
      final size = data.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (id == 0x64617461) {
        return Uint8List.sublistView(wav, offset, offset + size);
      }
      offset += size + (size.isOdd ? 1 : 0);
    }
    throw const FormatException('WAV has no data chunk');
  }
}
