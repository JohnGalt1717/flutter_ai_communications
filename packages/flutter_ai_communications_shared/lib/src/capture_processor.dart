/// Session-selected policy applied to the one Capture stream.
sealed class CaptureProcessor {
  /// Creates a processor.
  const CaptureProcessor();

  /// Acoustic-profile Baseline plus ambient/voice adaptation.
  const factory CaptureProcessor.adaptive() = AdaptiveCaptureProcessor;

  /// Acoustic-profile Baseline plus user step 1–10. No ambient adaptation.
  const factory CaptureProcessor.profileScaled(int step) =
      ProfileScaledCaptureProcessor;

  /// Absolute normalized RMS. No hidden profile multiplier.
  const factory CaptureProcessor.fixed(double normalizedRms) =
      FixedCaptureProcessor;

  /// No sound-floor rejection.
  const factory CaptureProcessor.passThrough() = PassThroughCaptureProcessor;
}

/// Adaptive Capture processor.
final class AdaptiveCaptureProcessor extends CaptureProcessor {
  /// Creates an adaptive processor.
  const AdaptiveCaptureProcessor();

  @override
  bool operator ==(Object other) => other is AdaptiveCaptureProcessor;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'CaptureProcessor.adaptive';
}

/// Profile-scaled Capture processor. Step 5 equals Baseline.
final class ProfileScaledCaptureProcessor extends CaptureProcessor {
  /// Creates a profile-scaled processor. [step] is clamped to 1–10.
  const ProfileScaledCaptureProcessor(int step)
    : step = step < 1
          ? 1
          : step > 10
          ? 10
          : step;

  /// User step. 5 is Baseline; higher rejects more.
  final int step;

  @override
  bool operator ==(Object other) =>
      other is ProfileScaledCaptureProcessor && other.step == step;

  @override
  int get hashCode => Object.hash(2, step);

  @override
  String toString() => 'CaptureProcessor.profileScaled($step)';
}

/// Absolute fixed-floor Capture processor.
final class FixedCaptureProcessor extends CaptureProcessor {
  /// Creates a fixed processor.
  const FixedCaptureProcessor(this.normalizedRms);

  /// Absolute 0–1 full-scale RMS.
  final double normalizedRms;

  @override
  bool operator ==(Object other) =>
      other is FixedCaptureProcessor && other.normalizedRms == normalizedRms;

  @override
  int get hashCode => Object.hash(3, normalizedRms);

  @override
  String toString() => 'CaptureProcessor.fixed($normalizedRms)';
}

/// Pass-through Capture processor.
final class PassThroughCaptureProcessor extends CaptureProcessor {
  /// Creates a pass-through processor.
  const PassThroughCaptureProcessor();

  @override
  bool operator ==(Object other) => other is PassThroughCaptureProcessor;

  @override
  int get hashCode => 4;

  @override
  String toString() => 'CaptureProcessor.passThrough';
}
