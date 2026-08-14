import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Pulse / PipeWire graph used by the Linux adapter.
abstract class AudioBackend {
  /// Snapshot of capture and render Endpoints.
  List<Endpoint> enumerate();

  /// Asks the OS whether capture is allowed. Must not leave a graph running.
  MicrophonePermission probePermission();

  /// Starts capture and render. Same subscription must survive restarts.
  NativeGraphStart start({String? captureId, String? renderId});

  /// Tears down the graph. Does not close Session streams.
  void stop();

  /// Parks capture and render.
  void pause();

  /// Resumes capture and render.
  void resume();

  /// Renders PCM16 LE mono frames.
  void play(Uint8List bytes);

  /// Applies an ephemeral Endpoint pick and restarts the graph.
  ///
  /// Must not clear pause and must not pretend to be an OS-forced route.
  void select({String? captureId, String? renderId});

  /// Drops queued playback.
  void flush();

  /// Raw capture frames, including silence on restart.
  Stream<Uint8List> get capture;

  /// Releases native resources.
  void dispose();
}
