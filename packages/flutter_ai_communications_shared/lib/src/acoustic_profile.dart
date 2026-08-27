import 'dart:math' as math;

import 'endpoint.dart';
import 'known_profile_registry.dart';

/// Acoustic family used to pick a Baseline sound floor.
enum AcousticFamily {
  /// Communications headset with near-mouth pickup.
  communicationsHeadset,

  /// Bluetooth loudspeaker.
  bluetoothSpeaker,

  /// Built-in tablet or laptop microphone.
  builtIn,

  /// Vehicle audio.
  car,

  /// Built-in loudspeaker path.
  speakerphone,

  /// Phone receiver.
  handset,

  /// Unclassified hardware.
  unknown,
}

/// How strongly an Acoustic profile is supported.
enum ProfileConfidence {
  /// Verified active native capabilities.
  verified,

  /// Narrow known-profile registry match.
  known,

  /// Conservative Route-class fallback.
  fallback,
}

/// Where an Acoustic profile came from.
enum ProfileProvenance {
  /// Native AEC/NS/AGC or form-factor metadata.
  nativeCapabilities,

  /// Shared known-profile registry.
  knownRegistry,

  /// Route class only.
  routeClass,
}

/// Evidence-backed Acoustic profile for an Endpoint.
final class AcousticProfile {
  /// Creates a profile.
  const AcousticProfile({
    required this.family,
    required this.baselineStep,
    required this.confidence,
    required this.provenance,
    this.hardwareNoiseProcessing = false,
    this.matchId,
  });

  /// Acoustic family.
  final AcousticFamily family;

  /// Seed Baseline step (1–10) before user scale or adaptation.
  final int baselineStep;

  /// Whether Endpoint hardware already suppresses noise on capture.
  final bool hardwareNoiseProcessing;

  /// How strongly this profile is supported.
  final ProfileConfidence confidence;

  /// Where the profile came from.
  final ProfileProvenance provenance;

  /// Registry match id, when a known profile was used.
  final String? matchId;

  @override
  bool operator ==(Object other) =>
      other is AcousticProfile &&
      other.family == family &&
      other.baselineStep == baselineStep &&
      other.hardwareNoiseProcessing == hardwareNoiseProcessing &&
      other.confidence == confidence &&
      other.provenance == provenance &&
      other.matchId == matchId;

  @override
  int get hashCode => Object.hash(
    family,
    baselineStep,
    hardwareNoiseProcessing,
    confidence,
    provenance,
    matchId,
  );
}

/// Shared known-profile table and classification precedence.
final class AcousticClassifier {
  /// Creates a classifier.
  const AcousticClassifier();

  /// Classifies [endpoint] using native family, then the registry, then Route
  /// class. Registry hardware noise processing lowers a headset Baseline only
  /// when the matched product is that family.
  AcousticProfile classify(Endpoint endpoint) {
    final nativeFamily = _nativeFamily(endpoint);
    final registry =
        KnownProfileRegistry.match(endpoint.identityHints) ??
        KnownProfileRegistry.match([endpoint.name]);
    final family =
        nativeFamily ??
        registry?.family ??
        _familyFromRoute(endpoint.routeClass);
    var hardwareNoiseProcessing = false;
    final matched = registry;
    if (matched != null &&
        (nativeFamily == null || matched.family == family)) {
      hardwareNoiseProcessing = matched.hardwareNoiseProcessing;
    }
    final provenance = nativeFamily != null
        ? ProfileProvenance.nativeCapabilities
        : registry != null
        ? ProfileProvenance.knownRegistry
        : ProfileProvenance.routeClass;
    final confidence = nativeFamily != null
        ? ProfileConfidence.verified
        : registry != null
        ? ProfileConfidence.known
        : ProfileConfidence.fallback;
    return AcousticProfile(
      family: family,
      baselineStep: BaselinePolicy.stepFor(
        family: family,
        hardwareNoiseProcessing: hardwareNoiseProcessing,
      ),
      hardwareNoiseProcessing: hardwareNoiseProcessing,
      confidence: confidence,
      provenance: provenance,
      matchId: registry?.id,
    );
  }

  AcousticFamily? _nativeFamily(Endpoint endpoint) {
    final caps = endpoint.capabilities;
    if (caps.formFactor == EndpointFormFactor.headset) {
      return AcousticFamily.communicationsHeadset;
    }
    if (caps.formFactor == EndpointFormFactor.speaker) {
      return AcousticFamily.bluetoothSpeaker;
    }
    if (caps.formFactor == EndpointFormFactor.handset) {
      return AcousticFamily.handset;
    }
    if (caps.formFactor == EndpointFormFactor.car ||
        caps.carConnected ||
        (endpoint.routeClass == RouteClass.car && caps.hasVerifiedNative)) {
      return AcousticFamily.car;
    }
    if (caps.aec && caps.ns && endpoint.routeClass == RouteClass.bluetooth) {
      return AcousticFamily.communicationsHeadset;
    }
    return null;
  }

  AcousticFamily _familyFromRoute(RouteClass routeClass) {
    return switch (routeClass) {
      RouteClass.handset => AcousticFamily.handset,
      RouteClass.speakerphone => AcousticFamily.speakerphone,
      RouteClass.car => AcousticFamily.car,
      RouteClass.wired => AcousticFamily.communicationsHeadset,
      RouteClass.bluetooth => AcousticFamily.bluetoothSpeaker,
    };
  }
}

/// Library-owned Baseline and profile-scaled RMS mapping.
abstract final class BaselinePolicy {
  static const double _stepOneRms = 0.012;
  static const double _stepRatio = 1.28;
  static const double _scaleRatio = 1.25;

  /// Seed Baseline step from family, lowered when hardware already
  /// suppresses capture noise.
  static int stepFor({
    required AcousticFamily family,
    required bool hardwareNoiseProcessing,
  }) {
    return switch (family) {
      AcousticFamily.communicationsHeadset => hardwareNoiseProcessing ? 3 : 4,
      AcousticFamily.bluetoothSpeaker => 4,
      AcousticFamily.car || AcousticFamily.builtIn => 5,
      AcousticFamily.speakerphone || AcousticFamily.unknown => 6,
      AcousticFamily.handset => 8,
    };
  }

  /// Seed RMS for a Baseline step 1–10.
  static double rmsForStep(int step) {
    final clamped = step.clamp(1, 10);
    return _stepOneRms * math.pow(_stepRatio, clamped - 1);
  }

  /// Profile-scaled RMS. Step 5 equals [profile] Baseline.
  static double rmsFor({
    required AcousticProfile profile,
    required int scaledStep,
  }) {
    final baseline = rmsForStep(profile.baselineStep);
    final offset = scaledStep.clamp(1, 10) - 5;
    return baseline * math.pow(_scaleRatio, offset);
  }
}
