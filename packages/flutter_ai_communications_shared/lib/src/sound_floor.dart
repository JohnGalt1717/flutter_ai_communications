import 'dart:typed_data';

import 'endpoint.dart';
import 'voice_metrics.dart';

/// Amplitude below which capture is treated as non-voice.
///
/// `null` fixed value means adaptive (voice band vs the rest; rises on
/// lounge / car / bad-BT and when Isolation is missing).
final class SoundFloor {
  /// Creates a floor. [fixed] is a 0–1 full-scale RMS, or `null` for adaptive.
  SoundFloor({this.fixed});

  static const _analyzer = VoiceAnalyzer();
  static const double _minAdaptive = 0.02;
  static const double _noiseMix = 0.12;
  static const double _adaptiveMargin = 2.4;

  /// Host-set fixed floor, or `null` for adaptive.
  double? fixed;
  double _noiseRms = _minAdaptive;

  /// Last adaptive noise estimate (0–1 RMS).
  double get noiseRms => _noiseRms;

  /// Sets a fixed floor or returns to adaptive when [value] is `null`.
  void setFloor(double? value) {
    fixed = value;
  }

  /// Active threshold after route / Isolation boosts.
  double threshold({
    RouteClass? routeClass,
    bool isolationMissing = false,
  }) {
    final base = fixed ?? (_noiseRms * _adaptiveMargin).clamp(_minAdaptive, 1.0);
    var boost = 1.0;
    if (routeClass == RouteClass.car || routeClass == RouteClass.bluetooth) {
      boost *= 1.6;
    }
    if (isolationMissing) {
      boost *= 1.35;
    }
    return (base * boost).clamp(0.0, 1.0);
  }

  /// [pcm] in PCM16 LE mono. Non-voice becomes silence of the same length.
  Uint8List apply(
    Uint8List pcm, {
    required int sampleRate,
    RouteClass? routeClass,
    bool isolationMissing = false,
  }) {
    final metrics = _analyzer.analyze(pcm, sampleRate);
    if (fixed == null && !metrics.isVoice) {
      _noiseRms = _noiseRms * (1 - _noiseMix) + metrics.rms * _noiseMix;
    }
    final floor = threshold(
      routeClass: routeClass,
      isolationMissing: isolationMissing,
    );
    final pass = metrics.rms >= floor && (fixed != null || metrics.isVoice);
    if (pass) {
      return pcm;
    }
    return Uint8List(pcm.length);
  }
}
