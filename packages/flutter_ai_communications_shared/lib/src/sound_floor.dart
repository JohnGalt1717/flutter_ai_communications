import 'dart:typed_data';

import 'acoustic_profile.dart';
import 'capture_processor.dart';
import 'endpoint.dart';
import 'voice_metrics.dart';

/// Amplitude below which capture is treated as non-voice.
///
/// Adaptive uses Acoustic-profile Baseline plus ambient/voice adaptation.
/// [CaptureProcessor.fixed] is an absolute RMS. `setFloor(null)` returns to
/// adaptive; `setFloor(0)` is pass-through compatibility.
final class SoundFloor {
  /// Creates a floor. [fixed] is a 0–1 full-scale RMS, or `null` for adaptive.
  SoundFloor({double? fixed, CaptureProcessor? processor, this.profile})
    : processor = processor ?? _legacyProcessor(fixed);

  static const _analyzer = VoiceAnalyzer();
  static const double _minAdaptive = 0.02;
  static const double _noiseMix = 0.12;
  static const double _adaptiveMargin = 2.4;
  static const double _isolationBoost = 1.35;
  static const double _legacyRouteBoost = 1.6;

  /// Active Capture processor.
  CaptureProcessor processor;

  /// Acoustic profile supplying the Baseline, when known.
  AcousticProfile? profile;

  double _noiseRms = _minAdaptive;

  /// Host-set fixed floor, or `null` when adaptive / profile-scaled.
  double? get fixed => switch (processor) {
    FixedCaptureProcessor(:final normalizedRms) => normalizedRms,
    PassThroughCaptureProcessor() => 0,
    _ => null,
  };

  set fixed(double? value) {
    processor = _legacyProcessor(value);
  }

  /// Last adaptive noise estimate (0–1 RMS).
  double get noiseRms => _noiseRms;

  /// Sets a fixed floor or returns to adaptive when [value] is `null`.
  void setFloor(double? value) {
    processor = _legacyProcessor(value);
  }

  /// Replaces the Capture processor.
  void setProcessor(CaptureProcessor value) {
    processor = value;
  }

  /// Adopts a profile and clears adaptive history when the family changes.
  void setProfile(AcousticProfile next) {
    final previous = profile;
    profile = next;
    if (previous != null && previous.family != next.family) {
      resetAdaptive();
    }
  }

  /// Clears ambient adaptation history.
  void resetAdaptive() {
    _noiseRms = _minAdaptive;
  }

  /// Active threshold after Isolation / legacy route boosts.
  double threshold({RouteClass? routeClass, bool isolationMissing = false}) {
    final base = switch (processor) {
      PassThroughCaptureProcessor() => 0.0,
      FixedCaptureProcessor(:final normalizedRms) => normalizedRms,
      ProfileScaledCaptureProcessor(:final step) =>
        profile == null
            ? BaselinePolicy.rmsForStep(step)
            : BaselinePolicy.rmsFor(profile: profile!, scaledStep: step),
      AdaptiveCaptureProcessor() =>
        (_noiseRms * _adaptiveMargin)
            .clamp(_minAdaptive, 1.0)
            .toDouble()
            .clamp(
              profile == null
                  ? 0.0
                  : BaselinePolicy.rmsForStep(profile!.baselineStep),
              1.0,
            ),
    };
    var boost = 1.0;
    if (profile == null &&
        (routeClass == RouteClass.car || routeClass == RouteClass.bluetooth)) {
      boost *= _legacyRouteBoost;
    }
    if (isolationMissing && processor is AdaptiveCaptureProcessor) {
      boost *= _isolationBoost;
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
    if (processor is PassThroughCaptureProcessor) {
      return pcm;
    }
    final metrics = _analyzer.analyze(pcm, sampleRate);
    if (processor is AdaptiveCaptureProcessor && !metrics.isVoice) {
      _noiseRms = _noiseRms * (1 - _noiseMix) + metrics.rms * _noiseMix;
    }
    final floor = threshold(
      routeClass: routeClass,
      isolationMissing: isolationMissing,
    );
    final requireVoice = processor is AdaptiveCaptureProcessor;
    final pass = metrics.rms >= floor && (!requireVoice || metrics.isVoice);
    if (pass) {
      return pcm;
    }
    return Uint8List(pcm.length);
  }

  static CaptureProcessor _legacyProcessor(double? fixed) {
    if (fixed == null) {
      return const CaptureProcessor.adaptive();
    }
    if (fixed == 0) {
      return const CaptureProcessor.passThrough();
    }
    return CaptureProcessor.fixed(fixed);
  }
}
