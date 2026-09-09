import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Method-channel encoding for a [VideoProcessor].
Map<String, Object?> videoProcessorToMap(VideoProcessor processor) =>
    switch (processor) {
      NoneVideoProcessor() => {'kind': 'none'},
      BlurVideoProcessor(:final intensity) => {
        'kind': 'blur',
        'intensity': intensity,
      },
      ReplaceVideoProcessor(:final bytes, :final asset) => {
        'kind': 'replace',
        if (bytes != null) 'bytes': Uint8List.fromList(bytes),
        if (asset != null) 'asset': asset,
      },
    };

/// Method-channel decoding for a [VideoProcessor].
VideoProcessor videoProcessorFromMap(Map<Object?, Object?> map) {
  final kind = map['kind'] as String? ?? 'none';
  return switch (kind) {
    'blur' => BlurVideoProcessor(intensity: map['intensity'] as int? ?? 50),
    'replace' => ReplaceVideoProcessor(
      bytes: switch (map['bytes']) {
        final Uint8List bytes => bytes,
        final List<int> bytes => bytes,
        _ => null,
      },
      asset: map['asset'] as String?,
    ),
    _ => const NoneVideoProcessor(),
  };
}
