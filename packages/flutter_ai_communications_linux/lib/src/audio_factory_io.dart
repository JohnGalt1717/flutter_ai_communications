import 'dart:io';

import 'audio_backend.dart';
import 'audio_unavailable.dart';
import 'pulse_backend.dart';

/// Linux hosts get Pulse / PipeWire; other `dart:io` hosts stay unavailable.
AudioBackend createAudioBackend() {
  if (Platform.isLinux) {
    try {
      return PulseAudioBackend();
    } on Object {
      return const UnavailableAudioBackend();
    }
  }
  return const UnavailableAudioBackend();
}
