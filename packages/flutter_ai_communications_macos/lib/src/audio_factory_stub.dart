import 'audio_backend.dart';
import 'audio_unavailable.dart';

/// Fallback when `dart:io` is unavailable.
AudioBackend createAudioBackend() => const UnavailableAudioBackend();
