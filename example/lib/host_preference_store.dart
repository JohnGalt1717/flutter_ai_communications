import 'dart:async';
import 'dart:convert';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host-owned persistence for Endpoint preference and Camera preference.
///
/// The library never writes these lists. Idle catalog picks and editor Apply
/// persist; live Session [Session.select] and [Session.selectCamera] do not.
final class HostPreferenceStore {
  /// Creates a store. [storage] is the durable map (in-memory or hydrated
  /// from the host's existing persistence). [persist] writes a key when
  /// preference changes.
  HostPreferenceStore({
    Map<String, String>? storage,
    Future<void> Function(String key, String value)? persist,
  }) : _storage = storage ?? <String, String>{},
       _persist = persist;

  /// Storage key for Endpoint preference JSON.
  static const endpointsKey = 'fac.endpointPreference';

  /// Storage key for Camera preference JSON.
  static const camerasKey = 'fac.cameraPreference';

  final Map<String, String> _storage;
  final Future<void> Function(String key, String value)? _persist;

  /// Persisted Endpoint preference. Empty means platform default.
  EndpointPreference get endpoints => _decodeEndpoints(_storage[endpointsKey]);

  /// Persisted Camera preference. Empty means intelligent default.
  CameraPreference get cameras => _decodeCameras(_storage[camerasKey]);

  /// Replaces Endpoint preference.
  void saveEndpoints(EndpointPreference preference) {
    _write(endpointsKey, [
      for (final entry in preference.entries)
        if (entry.captures.isNotEmpty)
          {
            'renderId': entry.renderId,
            'enabled': entry.enabled,
            'captures': [
              for (final slot in entry.captures)
                {'id': slot.id, 'enabled': slot.enabled},
            ],
          },
    ]);
  }

  /// Promotes [endpoint] into Endpoint preference using the live catalog.
  ///
  /// A render Endpoint becomes a row (capture list is the hardware mate or
  /// the existing list with that mate first). A capture Endpoint promotes
  /// its hardware-Pair render row. Unpaired captures are not rows.
  void preferEndpoint(Endpoint endpoint, List<Endpoint> catalog) {
    final render = endpoint.isCapture
        ? catalog
              .where(
                (item) => item.pairId == endpoint.pairId && !item.isCapture,
              )
              .firstOrNull
        : endpoint;
    if (render == null || render.isCapture) {
      return;
    }
    final mateId = endpoint.isCapture
        ? endpoint.id
        : catalog
              .where((item) => item.pairId == endpoint.pairId && item.isCapture)
              .firstOrNull
              ?.id;
    final existing = endpoints.entries
        .where((entry) => entry.renderId == render.id)
        .firstOrNull;
    final captures = <EndpointPreferenceCapture>[
      if (mateId != null) EndpointPreferenceCapture(id: mateId),
      if (existing != null)
        for (final slot in existing.captures)
          if (slot.id != mateId) slot,
    ];
    if (captures.isEmpty) {
      return;
    }
    saveEndpoints(
      EndpointPreference(
        entries: [
          EndpointPreferenceEntry(
            renderId: render.id,
            enabled: existing?.enabled ?? true,
            captures: captures,
          ),
          for (final entry in endpoints.entries)
            if (entry.renderId != render.id) entry,
        ],
      ),
    );
  }

  /// Promotes [id] to the front of Camera preference.
  void preferCamera(String id) {
    _write(camerasKey, [
      {'id': id, 'enabled': true},
      for (final entry in cameras.entries)
        if (entry.id != id) {'id': entry.id, 'enabled': entry.enabled},
    ]);
  }

  void _write(String key, List<Map<String, Object>> entries) {
    final encoded = jsonEncode(entries);
    _storage[key] = encoded;
    final persist = _persist;
    if (persist != null) {
      unawaited(persist(key, encoded));
    }
  }

  EndpointPreference _decodeEndpoints(String? raw) {
    final decoded = _decodeList(raw);
    if (decoded == null) {
      return const EndpointPreference();
    }
    final entries = <EndpointPreferenceEntry>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final renderId = item['renderId'];
      if (renderId is! String || renderId.isEmpty) {
        continue;
      }
      final captures = <EndpointPreferenceCapture>[];
      final slots = item['captures'];
      if (slots is List) {
        for (final slot in slots) {
          if (slot is Map && slot['id'] is String) {
            captures.add(
              EndpointPreferenceCapture(
                id: slot['id'] as String,
                enabled: slot['enabled'] is bool
                    ? slot['enabled'] as bool
                    : true,
              ),
            );
          }
        }
      }
      if (captures.isEmpty) {
        continue;
      }
      entries.add(
        EndpointPreferenceEntry(
          renderId: renderId,
          enabled: item['enabled'] is bool ? item['enabled'] as bool : true,
          captures: captures,
        ),
      );
    }
    return EndpointPreference(entries: entries);
  }

  CameraPreference _decodeCameras(String? raw) {
    final decoded = _decodeList(raw);
    if (decoded == null) {
      return const CameraPreference();
    }
    return CameraPreference(
      entries: [
        for (final item in decoded)
          if (item is Map && item['id'] is String)
            CameraPreferenceEntry(
              id: item['id'] as String,
              enabled: item['enabled'] is bool ? item['enabled'] as bool : true,
            ),
      ],
    );
  }

  List<dynamic>? _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    return decoded is List<dynamic> ? decoded : null;
  }
}
