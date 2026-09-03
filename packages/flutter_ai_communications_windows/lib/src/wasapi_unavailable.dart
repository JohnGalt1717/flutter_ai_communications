import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'wasapi_backend.dart';

/// Used when WASAPI cannot be loaded (tests on non-Windows hosts).
final class UnavailableWasapiBackend implements WasapiBackend {
  /// Creates an unavailable backend.
  const UnavailableWasapiBackend();

  @override
  List<Endpoint> enumerate() => const [];

  @override
  MicrophonePermission probePermission() => MicrophonePermission.denied;

  @override
  NativeGraphStart start({String? captureId, String? renderId}) =>
      NativeGraphStart.unavailable;

  @override
  void stop() {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void play(Uint8List bytes) {}

  @override
  void select({String? captureId, String? renderId}) {}

  @override
  PairingSnapshot get observed => const PairingSnapshot();

  @override
  NativeFormatReport get nativeFormats => const NativeFormatReport();

  @override
  void flush() {}

  @override
  Stream<Uint8List> get capture => const Stream.empty();

  @override
  bool startLoopback() => false;

  @override
  void stopLoopback() {}

  @override
  Stream<Uint8List> get loopback => const Stream.empty();

  @override
  void dispose() {}
}
