import 'dart:math' as math;
import 'dart:typed_data';

/// RMS and voice-band ratio for a PCM16 LE mono frame.
final class VoiceMetrics {
  /// Creates metrics.
  const VoiceMetrics({required this.rms, required this.voiceBandRatio});

  /// RMS as a fraction of full scale (0–1).
  final double rms;

  /// Energy in ~300–3400 Hz over total energy.
  final double voiceBandRatio;

  /// Likely user speech, not lounge rumble.
  bool get isVoice => rms > 0.03 && voiceBandRatio > 0.45;
}

/// Cheap voice-band analysis. Not a production VAD.
final class VoiceAnalyzer {
  /// Creates an analyzer.
  const VoiceAnalyzer();

  /// Analyzes [bytes] as PCM16 LE mono at [sampleRate].
  VoiceMetrics analyze(Uint8List bytes, int sampleRate) {
    if (bytes.length < 4 || sampleRate <= 0) {
      return const VoiceMetrics(rms: 0, voiceBandRatio: 0);
    }
    final data = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    var sumSq = 0.0;
    var bandSq = 0.0;
    var lp300 = 0.0;
    var lp3400 = 0.0;
    final a300 = _onePole(300, sampleRate);
    final a3400 = _onePole(3400, sampleRate);
    for (var i = 0; i < n; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSq += sample * sample;
      lp300 += a300 * (sample - lp300);
      lp3400 += a3400 * (sample - lp3400);
      final band = lp3400 - lp300;
      bandSq += band * band;
    }
    final rms = math.sqrt(sumSq / n);
    final bandRms = math.sqrt(bandSq / n);
    final ratio = rms == 0 ? 0.0 : (bandRms / rms).clamp(0.0, 1.0);
    return VoiceMetrics(rms: rms, voiceBandRatio: ratio);
  }

  double _onePole(double hz, int sampleRate) {
    final x = 1 - math.exp(-2 * math.pi * hz / sampleRate);
    return x.clamp(0.0, 1.0);
  }
}
