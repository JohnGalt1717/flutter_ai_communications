import 'dart:convert';

import 'acoustic_profile.dart';
import 'data/known_profiles.embed.dart';

/// One researched known-profile row.
final class KnownProfile {
  /// Creates a registry row.
  const KnownProfile({
    required this.id,
    required this.aliases,
    required this.family,
    required this.hardwareNoiseProcessing,
    required this.sources,
  });

  /// Parses one JSON object.
  factory KnownProfile.fromJson(Map<String, dynamic> json) {
    return KnownProfile(
      id: json['id'] as String,
      aliases: [
        for (final alias in json['aliases'] as List<dynamic>) alias as String,
      ],
      family: _family(json['family'] as String),
      hardwareNoiseProcessing: json['hardwareNoiseProcessing'] as bool,
      sources: [
        for (final source in json['sources'] as List<dynamic>) source as String,
      ],
    );
  }

  /// Stable id used as [AcousticProfile.matchId].
  final String id;

  /// Normalized advertised-name tokens. Longer / more specific rows first.
  final List<String> aliases;

  /// Acoustic family for this product.
  final AcousticFamily family;

  /// Whether this hardware already suppresses noise on capture.
  final bool hardwareNoiseProcessing;

  /// Primary sources that document the advertised name and processing.
  final List<String> sources;
}

AcousticFamily _family(String name) => switch (name) {
  'communicationsHeadset' => AcousticFamily.communicationsHeadset,
  'bluetoothSpeaker' => AcousticFamily.bluetoothSpeaker,
  'car' => AcousticFamily.car,
  'builtIn' => AcousticFamily.builtIn,
  'speakerphone' => AcousticFamily.speakerphone,
  'handset' => AcousticFamily.handset,
  _ => AcousticFamily.unknown,
};

/// Loads and matches the known-profile JSON.
abstract final class KnownProfileRegistry {
  static List<KnownProfile>? _cache;

  /// Parsed rows. First match wins, so the JSON is ordered specific → general.
  static List<KnownProfile> load([String json = knownProfilesJson]) {
    if (json == knownProfilesJson && _cache != null) {
      return _cache!;
    }
    final decoded = jsonDecode(json) as List<dynamic>;
    final rows = [
      for (final row in decoded)
        KnownProfile.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    if (json == knownProfilesJson) {
      _cache = rows;
    }
    return rows;
  }

  /// First row whose alias is a whole-token match in [rawNames].
  static KnownProfile? match(Iterable<String> rawNames) {
    final names = rawNames.map(_normalize).where((name) => name.isNotEmpty);
    for (final name in names) {
      for (final entry in load()) {
        if (entry.aliases.any(
          (alias) => _containsAlias(name, _normalize(alias)),
        )) {
          return entry;
        }
      }
    }
    return null;
  }
}

String _normalize(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

bool _containsAlias(String name, String alias) {
  if (alias.isEmpty) {
    return false;
  }
  if (name == alias) {
    return true;
  }
  return name.startsWith('$alias ') ||
      name.endsWith(' $alias') ||
      name.contains(' $alias ');
}
