import 'audio_backend.dart';
import 'audio_factory_stub.dart'
    if (dart.library.io) 'audio_factory_io.dart'
    as impl;

/// Creates the Pulse backend for this host.
AudioBackend createAudioBackend() => impl.createAudioBackend();
