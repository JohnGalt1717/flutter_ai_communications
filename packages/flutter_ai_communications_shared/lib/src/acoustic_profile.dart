import 'dart:math' as math;

import 'endpoint.dart';

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
    this.matchId,
  });

  /// Acoustic family.
  final AcousticFamily family;

  /// Seed Baseline step (1–10) before user scale or adaptation.
  final int baselineStep;

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
      other.confidence == confidence &&
      other.provenance == provenance &&
      other.matchId == matchId;

  @override
  int get hashCode =>
      Object.hash(family, baselineStep, confidence, provenance, matchId);
}

/// Shared known-profile table and classification precedence.
final class AcousticClassifier {
  /// Creates a classifier.
  const AcousticClassifier();

  static const List<_RegistryEntry> _registry = [
    _RegistryEntry(
      id: 'airpods',
      aliases: ['airpods'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'jabra-evolve',
      aliases: ['jabra evolve', 'jabra evolve2'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'plantronics',
      aliases: ['plantronics', 'poly voyager', 'poly blackwire'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'bose-qc',
      aliases: ['bose qc', 'bose quietcomfort'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'sony-wh-wf',
      aliases: ['sony wh', 'sony wf'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'beats',
      aliases: ['beats'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'sennheiser',
      aliases: ['sennheiser'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'soundcore',
      aliases: ['soundcore'],
      family: AcousticFamily.communicationsHeadset,
      baselineStep: 3,
    ),
    _RegistryEntry(
      id: 'jbl-flip',
      aliases: ['jbl flip'],
      family: AcousticFamily.bluetoothSpeaker,
      baselineStep: 4,
    ),
  ];

  /// Classifies [endpoint] using native capabilities, then the registry, then
  /// Route class. Vehicle tokens require independent car evidence.
  AcousticProfile classify(Endpoint endpoint) {
    final native = _fromCapabilities(endpoint);
    if (native != null) {
      return native;
    }
    final known = _fromRegistry(endpoint);
    if (known != null) {
      return known;
    }
    return _fromRoute(endpoint.routeClass);
  }

  AcousticProfile? _fromCapabilities(Endpoint endpoint) {
    final caps = endpoint.capabilities;
    if (caps.formFactor == EndpointFormFactor.headset) {
      return const AcousticProfile(
        family: AcousticFamily.communicationsHeadset,
        baselineStep: 3,
        confidence: ProfileConfidence.verified,
        provenance: ProfileProvenance.nativeCapabilities,
      );
    }
    if (caps.formFactor == EndpointFormFactor.speaker) {
      return const AcousticProfile(
        family: AcousticFamily.bluetoothSpeaker,
        baselineStep: 4,
        confidence: ProfileConfidence.verified,
        provenance: ProfileProvenance.nativeCapabilities,
      );
    }
    if (caps.formFactor == EndpointFormFactor.handset) {
      return const AcousticProfile(
        family: AcousticFamily.handset,
        baselineStep: 8,
        confidence: ProfileConfidence.verified,
        provenance: ProfileProvenance.nativeCapabilities,
      );
    }
    if (caps.formFactor == EndpointFormFactor.car ||
        caps.carConnected ||
        (endpoint.routeClass == RouteClass.car && caps.hasVerifiedNative)) {
      return const AcousticProfile(
        family: AcousticFamily.car,
        baselineStep: 5,
        confidence: ProfileConfidence.verified,
        provenance: ProfileProvenance.nativeCapabilities,
      );
    }
    if (caps.aec && caps.ns && endpoint.routeClass == RouteClass.bluetooth) {
      return const AcousticProfile(
        family: AcousticFamily.communicationsHeadset,
        baselineStep: 3,
        confidence: ProfileConfidence.verified,
        provenance: ProfileProvenance.nativeCapabilities,
      );
    }
    return null;
  }

  AcousticProfile? _fromRegistry(Endpoint endpoint) {
    if (endpoint.routeClass == RouteClass.car &&
        !endpoint.capabilities.carConnected) {
      return null;
    }
    final name = _normalize(endpoint.name);
    for (final entry in _registry) {
      if (entry.aliases.any((alias) => _containsAlias(name, alias))) {
        return AcousticProfile(
          family: entry.family,
          baselineStep: entry.baselineStep,
          confidence: ProfileConfidence.known,
          provenance: ProfileProvenance.knownRegistry,
          matchId: entry.id,
        );
      }
    }
    return null;
  }

  AcousticProfile _fromRoute(RouteClass routeClass) {
    return switch (routeClass) {
      RouteClass.handset => const AcousticProfile(
        family: AcousticFamily.handset,
        baselineStep: 8,
        confidence: ProfileConfidence.fallback,
        provenance: ProfileProvenance.routeClass,
      ),
      RouteClass.speakerphone => const AcousticProfile(
        family: AcousticFamily.speakerphone,
        baselineStep: 6,
        confidence: ProfileConfidence.fallback,
        provenance: ProfileProvenance.routeClass,
      ),
      RouteClass.car => const AcousticProfile(
        family: AcousticFamily.car,
        baselineStep: 5,
        confidence: ProfileConfidence.fallback,
        provenance: ProfileProvenance.routeClass,
      ),
      RouteClass.wired => const AcousticProfile(
        family: AcousticFamily.communicationsHeadset,
        baselineStep: 3,
        confidence: ProfileConfidence.fallback,
        provenance: ProfileProvenance.routeClass,
      ),
      RouteClass.bluetooth => const AcousticProfile(
        family: AcousticFamily.bluetoothSpeaker,
        baselineStep: 4,
        confidence: ProfileConfidence.fallback,
        provenance: ProfileProvenance.routeClass,
      ),
    };
  }

  String _normalize(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  bool _containsAlias(String name, String alias) {
    if (name == alias) {
      return true;
    }
    return name.startsWith('$alias ') ||
        name.endsWith(' $alias') ||
        name.contains(' $alias ');
  }
}

/// Library-owned Baseline and profile-scaled RMS mapping.
abstract final class BaselinePolicy {
  static const double _stepOneRms = 0.012;
  static const double _stepRatio = 1.28;
  static const double _scaleRatio = 1.25;

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

final class _RegistryEntry {
  const _RegistryEntry({
    required this.id,
    required this.aliases,
    required this.family,
    required this.baselineStep,
  });

  final String id;
  final List<String> aliases;
  final AcousticFamily family;
  final int baselineStep;
}
