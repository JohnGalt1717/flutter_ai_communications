import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'camera_permission.dart';
import 'isolation.dart';
import 'microphone_permission.dart';
import 'native_graph_start.dart';
import 'platform_events.dart';

/// The platform seam for the Audio manager.
///
/// Platform packages extend this class and register themselves. New Session
/// methods default to [UnimplementedError] so older adapters still load.
abstract class FlutterAiCommunicationsPlatform extends PlatformInterface {
  /// Creates a platform interface token holder.
  FlutterAiCommunicationsPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAiCommunicationsPlatform? _instance;

  /// The current platform adapter, if one has registered.
  static FlutterAiCommunicationsPlatform get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError(
        'FlutterAiCommunicationsPlatform.instance has not been set. '
        'Register a platform adapter or inject a fake in tests.',
      );
    }
    return instance;
  }

  /// Sets the current platform adapter.
  static set instance(FlutterAiCommunicationsPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Whether a platform adapter has registered.
  static bool get isRegistered => _instance != null;

  /// Clears the registered adapter. Tests only.
  static void debugReset() {
    _instance = null;
  }

  /// Platform identifier used to prove the federated wiring resolved.
  String get platformName;

  /// Snapshot of capture and render Endpoints.
  Future<List<Endpoint>> enumerateEndpoints() {
    throw UnimplementedError('enumerateEndpoints() has not been implemented.');
  }

  /// Live catalog updates. Defaults to a single [enumerateEndpoints] snapshot.
  Stream<List<Endpoint>> get endpointCatalog async* {
    yield await enumerateEndpoints();
  }

  /// Requests the microphone and waits for the OS answer.
  Future<MicrophonePermission> requestMicrophonePermission() {
    throw UnimplementedError(
      'requestMicrophonePermission() has not been implemented.',
    );
  }

  /// Starts the native capture/render graph.
  ///
  /// [captureFormat] and [playbackFormat] are the Session edge Formats.
  /// After [NativeGraphStart.started], [lastNativeFormats] holds the
  /// negotiated Native Formats.
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    bool noiseCancelling = true,
  }) {
    throw UnimplementedError('startNative() has not been implemented.');
  }

  /// Native Formats from the last start, reset, or Endpoint apply.
  NativeFormatReport get lastNativeFormats => const NativeFormatReport();

  /// Stops the native graph. Does not replace Session streams.
  Future<void> stopNative() {
    throw UnimplementedError('stopNative() has not been implemented.');
  }

  /// Tears down and rebuilds the native graph without replacing Session streams.
  Future<NativeGraphStart> resetNative({
    String? captureId,
    String? renderId,
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    bool noiseCancelling = true,
  }) async {
    await stopNative();
    return startNative(
      captureId: captureId,
      renderId: renderId,
      captureFormat: captureFormat,
      playbackFormat: playbackFormat,
      noiseCancelling: noiseCancelling,
    );
  }

  /// Pauses native capture and render without tearing down Session streams.
  Future<void> pauseNative() {
    throw UnimplementedError('pauseNative() has not been implemented.');
  }

  /// Resumes native capture and render on the same graph.
  Future<void> resumeNative() {
    throw UnimplementedError('resumeNative() has not been implemented.');
  }

  /// Raw capture frames from the native graph.
  Stream<Uint8List> get nativeCapture {
    throw UnimplementedError('nativeCapture has not been implemented.');
  }

  /// Renders [bytes] on the current render Endpoint.
  Future<void> play(Uint8List bytes) {
    throw UnimplementedError('play() has not been implemented.');
  }

  /// Applies an ephemeral Endpoint pick. Must not persist preference.
  Future<void> selectEndpoints({String? captureId, String? renderId}) {
    throw UnimplementedError('selectEndpoints() has not been implemented.');
  }

  /// Isolation detection. Platforms that cannot detect emit unavailable.
  Stream<IsolationEvent> get isolation {
    throw UnimplementedError('isolation has not been implemented.');
  }

  /// Last Isolation event. Session replays this when it attaches.
  IsolationEvent get lastIsolation =>
      const IsolationEvent(IsolationState.unknown);

  /// Opens the system Isolation UI when the platform supports it.
  Future<void> openIsolationSettings() {
    throw UnimplementedError(
      'openIsolationSettings() has not been implemented.',
    );
  }

  /// Drops queued playback immediately (local barge-in).
  Future<void> flushPlayback() {
    throw UnimplementedError('flushPlayback() has not been implemented.');
  }

  /// Audio-path Coverage from the native graph (route death).
  Stream<CoverageHint> get pathCoverage => const Stream.empty();

  /// Phone-call / audio-focus interruptions.
  Stream<AudioFocusState> get audioFocus => const Stream.empty();

  /// OS-forced Endpoint changes.
  Stream<OsRouteChange> get osRouteChanges => const Stream.empty();

  /// Last Observed Pair reported by the platform, if any.
  ///
  /// Command completion is not observation. Adapters update this only from
  /// native route state.
  PairingSnapshot get lastObservedRoute => const PairingSnapshot();

  /// Snapshot of Camera Endpoints. Defaults unimplemented so older adapters load.
  Future<List<CameraEndpoint>> enumerateCameras() {
    throw UnimplementedError('enumerateCameras() has not been implemented.');
  }

  /// Requests the camera and waits for the OS answer.
  Future<CameraPermission> requestCameraPermission() {
    throw UnimplementedError(
      'requestCameraPermission() has not been implemented.',
    );
  }

  /// Starts the native camera graph. Does not fail the audio Session.
  Future<NativeGraphStart> startCameraNative({
    String? cameraId,
    VideoFormat? videoFormat,
    bool enabled = true,
    bool muted = false,
  }) {
    throw UnimplementedError('startCameraNative() has not been implemented.');
  }

  /// Stops the native camera graph without ending the Session.
  Future<void> stopCameraNative() async {}

  /// Ephemeral camera pick. Must not persist Camera preference.
  Future<void> selectCameraNative(String cameraId) {
    throw UnimplementedError('selectCameraNative() has not been implemented.');
  }

  /// Camera-off when [enabled] is false; hardware may stop.
  Future<void> setCameraEnabledNative(bool enabled) {
    throw UnimplementedError(
      'setCameraEnabledNative() has not been implemented.',
    );
  }

  /// Mute-video substitutes black frames; the graph stays up.
  Future<void> setMuteVideoNative(bool muted) {
    throw UnimplementedError('setMuteVideoNative() has not been implemented.');
  }

  /// Last Video surface from camera start, if any.
  VideoSurface? get lastVideoSurface => null;

  /// Negotiated Native Video Format from the last camera start.
  VideoFormat? get lastNativeVideoFormat => null;

  /// Native captured frames since the last camera start. Not a Dart byte tap.
  int get lastCameraFrameCount => 0;

  /// Frames that contained non-black pixels. Proves the sensor is live.
  int get lastCameraLiveFrames => 0;

  /// Refreshes [lastCameraFrameCount] and [lastCameraLiveFrames] from native.
  Future<void> pollCameraNative() async {}
}
