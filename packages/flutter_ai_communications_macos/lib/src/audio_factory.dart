import 'audio_backend.dart';
import 'audio_factory_stub.dart'
    if (dart.library.io) 'audio_factory_io.dart'
    as impl;

/// Creates a legacy FFI backend for hosts that still inject one.
///
/// Production duplex capture/playback is the native AVAudioEngine plugin.
AudioBackend createAudioBackend() => impl.createAudioBackend();
