import 'dart:math' as math;
import 'dart:typed_data';

/// Peak / clip / RMS checks for PCM16 LE mono.
final class PcmQuality {
  /// Absolute peak sample.
  static int peak(Uint8List pcm) {
    if (pcm.length < 2) {
      return 0;
    }
    final data = ByteData.sublistView(pcm);
    var max = 0;
    for (var i = 0; i < pcm.length ~/ 2; i++) {
      final sample = data.getInt16(i * 2, Endian.little).abs();
      if (sample > max) {
        max = sample;
      }
    }
    return max;
  }

  /// True when any sample is at full scale.
  static bool clipped(Uint8List pcm) {
    if (pcm.length < 2) {
      return false;
    }
    final data = ByteData.sublistView(pcm);
    for (var i = 0; i < pcm.length ~/ 2; i++) {
      final sample = data.getInt16(i * 2, Endian.little);
      if (sample >= 32767 || sample <= -32768) {
        return true;
      }
    }
    return false;
  }

  /// RMS as a fraction of full scale.
  static double rms(Uint8List pcm) {
    if (pcm.length < 2) {
      return 0;
    }
    final data = ByteData.sublistView(pcm);
    var sum = 0.0;
    final n = pcm.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += sample * sample;
    }
    return math.sqrt(sum / n);
  }
}
