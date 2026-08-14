import 'dart:io';

import 'audio_backend.dart';
import 'audio_unavailable.dart';
import 'core_audio_backend.dart';

/// macOS hosts get Core Audio; other `dart:io` hosts stay unavailable.
AudioBackend createAudioBackend() {
  if (Platform.isMacOS) {
    try {
      return CoreAudioBackend();
    } on Object {
      return const UnavailableAudioBackend();
    }
  }
  return const UnavailableAudioBackend();
}
