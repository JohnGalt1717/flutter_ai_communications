import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'camera_permission.dart';
import 'flutter_ai_communications_platform.dart';
import 'isolation.dart';
import 'microphone_permission.dart';
import 'native_graph_start.dart';
import 'platform_events.dart';

/// In-memory adapter for tests. Does not touch a real device.
final class FakeCommunicationsPlatform extends FlutterAiCommunicationsPlatform {
  /// Creates a fake adapter.
  FakeCommunicationsPlatform({
    this.permission = MicrophonePermission.granted,
    this.cameraPermission = CameraPermission.granted,
    this.nativeStart = NativeGraphStart.started,
    List<Endpoint>? catalog,
    List<CameraEndpoint>? cameras,
  }) : catalog = List<Endpoint>.of(catalog ?? defaultCatalog),
       cameras = List<CameraEndpoint>.of(cameras ?? defaultCameras);

  /// Built-in handset and speakerphone Endpoints.
  static const List<Endpoint> defaultCatalog = [
    Endpoint(
      id: 'handset-in',
      name: 'Handset',
      routeClass: RouteClass.handset,
      isCapture: true,
    ),
    Endpoint(
      id: 'handset-out',
      name: 'Handset',
      routeClass: RouteClass.handset,
      isCapture: false,
    ),
    Endpoint(
      id: 'speaker-in',
      name: 'Speakerphone',
      routeClass: RouteClass.speakerphone,
      isCapture: true,
    ),
    Endpoint(
      id: 'speaker-out',
      name: 'Speakerphone',
      routeClass: RouteClass.speakerphone,
      isCapture: false,
    ),
    Endpoint(
      id: 'airpods-in',
      name: 'AirPods',
      routeClass: RouteClass.bluetooth,
      isCapture: true,
      pairId: 'airpods',
    ),
    Endpoint(
      id: 'airpods-out',
      name: 'AirPods',
      routeClass: RouteClass.bluetooth,
      isCapture: false,
      pairId: 'airpods',
    ),
  ];

  /// Built-in front and back cameras.
  static const List<CameraEndpoint> defaultCameras = [
    CameraEndpoint(
      id: 'front',
      name: 'Front',
      facing: CameraFacing.user,
      modes: [VideoFormat.defaultFormat],
    ),
    CameraEndpoint(
      id: 'back',
      name: 'Back',
      facing: CameraFacing.environment,
      modes: [
        VideoFormat(width: 1920, height: 1080, frameRate: 30),
        VideoFormat.defaultFormat,
      ],
    ),
  ];

  /// Permission [requestMicrophonePermission] returns.
  MicrophonePermission permission;

  /// Result of [startNative].
  NativeGraphStart nativeStart;

  /// Current catalog snapshot.
  List<Endpoint> catalog;

  /// Optional error thrown from [startNative].
  Object? startNativeError;

  /// Capture frames tests inject.
  final StreamController<Uint8List> captureController =
      StreamController<Uint8List>.broadcast();

  /// Isolation events tests inject.
  final StreamController<IsolationEvent> isolationController =
      StreamController<IsolationEvent>.broadcast();

  /// Catalog updates tests inject.
  final StreamController<List<Endpoint>> catalogController =
      StreamController<List<Endpoint>>.broadcast();

  /// Native path Coverage tests inject.
  final StreamController<CoverageHint> pathCoverageController =
      StreamController<CoverageHint>.broadcast();

  /// Audio-focus events tests inject.
  final StreamController<AudioFocusState> audioFocusController =
      StreamController<AudioFocusState>.broadcast();

  /// OS-forced route changes tests inject.
  final StreamController<OsRouteChange> osRouteController =
      StreamController<OsRouteChange>.broadcast();

  /// Bytes passed to [play], in order.
  final List<Uint8List> played = <Uint8List>[];

  /// Last ephemeral or start capture id.
  String? selectedCaptureId;

  /// Last ephemeral or start render id.
  String? selectedRenderId;

  /// Whether the native graph is running.
  bool nativeRunning = false;

  /// Whether the native graph is paused.
  bool nativePaused = false;

  /// How many times [startNative] ran.
  int startNativeCalls = 0;

  /// How many times [requestMicrophonePermission] ran.
  int permissionRequests = 0;

  /// When true, apply/start updates [lastObservedRoute] and may emit an OS route.
  bool observeOnApply = true;

  /// Last Observed Pair. Command completion does not write this unless
  /// [observeOnApply] is true.
  PairingSnapshot observedRoute = const PairingSnapshot();

  /// How many times [openIsolationSettings] ran.
  int openIsolationSettingsCalls = 0;

  /// How many times [flushPlayback] ran.
  int flushPlaybackCalls = 0;

  /// Optional error thrown from [stopNative].
  Object? stopNativeError;

  /// When set, [stopNative] waits until this completes.
  Completer<void>? stopNativeGate;

  /// How many times [resetNative] ran.
  int resetNativeCalls = 0;

  /// How many times [selectEndpoints] ran.
  int selectEndpointsCalls = 0;

  /// Monotonic native graph generation.
  int nativeGeneration = 0;

  /// Native capture Format returned after start. Defaults to the requested edge.
  AudioFormat? nativeCaptureFormat;

  /// Native playback Format returned after start. Defaults to the requested edge.
  AudioFormat? nativePlaybackFormat;

  NativeFormatReport _lastNativeFormats = const NativeFormatReport();

  @override
  NativeFormatReport get lastNativeFormats => _lastNativeFormats;

  /// Last Isolation event, replayed when a Session attaches.
  IsolationEvent lastIsolationEvent = const IsolationEvent(
    IsolationState.unknown,
  );

  @override
  IsolationEvent get lastIsolation => lastIsolationEvent;

  /// Injects a capture frame as the native graph would.
  void feedCapture(Uint8List bytes) {
    captureController.add(bytes);
  }

  @override
  String get platformName => 'fake';

  @override
  Future<List<Endpoint>> enumerateEndpoints() async => List<Endpoint>.of(catalog);

  @override
  Stream<List<Endpoint>> get endpointCatalog => catalogController.stream;

  /// Replaces the catalog and broadcasts it.
  void publishCatalog(List<Endpoint> next) {
    catalog = List<Endpoint>.of(next);
    catalogController.add(List<Endpoint>.of(catalog));
  }

  @override
  PairingSnapshot get lastObservedRoute => observedRoute;

  @override
  Future<MicrophonePermission> requestMicrophonePermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    bool noiseCancelling = true,
  }) async {
    startNativeCalls++;
    nativeGeneration++;
    final error = startNativeError;
    if (error != null) {
      throw error;
    }
    if (nativeStart != NativeGraphStart.started) {
      return nativeStart;
    }
    _lastNativeFormats = NativeFormatReport(
      capture: nativeCaptureFormat ?? captureFormat,
      playback: nativePlaybackFormat ?? playbackFormat,
    );
    selectedCaptureId =
        captureId ??
        catalog.where((endpoint) => endpoint.isCapture).firstOrNull?.id;
    selectedRenderId =
        renderId ??
        catalog.where((endpoint) => !endpoint.isCapture).firstOrNull?.id;
    nativeRunning = true;
    nativePaused = false;
    lastIsolationEvent = IsolationEvent(
      noiseCancelling ? IsolationState.off : IsolationState.unavailable,
    );
    isolationController.add(lastIsolationEvent);
    _maybeObserveApplied();
    return NativeGraphStart.started;
  }

  @override
  Future<void> stopNative() async {
    final gate = stopNativeGate;
    if (gate != null) {
      await gate.future;
    }
    nativeRunning = false;
    nativePaused = false;
    final error = stopNativeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<NativeGraphStart> resetNative({
    String? captureId,
    String? renderId,
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    bool noiseCancelling = true,
  }) async {
    resetNativeCalls++;
    await stopNative();
    return startNative(
      captureId: captureId,
      renderId: renderId,
      captureFormat: captureFormat,
      playbackFormat: playbackFormat,
      noiseCancelling: noiseCancelling,
    );
  }

  @override
  Future<void> pauseNative() async {
    nativePaused = true;
  }

  @override
  Future<void> resumeNative() async {
    nativePaused = false;
  }

  @override
  Stream<Uint8List> get nativeCapture => captureController.stream;

  @override
  Future<void> play(Uint8List bytes) async {
    if (!nativeRunning || nativePaused) {
      return;
    }
    played.add(bytes);
  }

  @override
  Future<void> selectEndpoints({String? captureId, String? renderId}) async {
    selectEndpointsCalls++;
    if (captureId != null) {
      selectedCaptureId = captureId;
    }
    if (renderId != null) {
      selectedRenderId = renderId;
    }
    _maybeObserveApplied();
  }

  void _maybeObserveApplied() {
    if (!observeOnApply) {
      return;
    }
    observedRoute = PairingSnapshot(
      captureId: selectedCaptureId,
      renderId: selectedRenderId,
    );
    osRouteController.add(
      OsRouteChange(
        captureId: selectedCaptureId,
        renderId: selectedRenderId,
        generation: nativeGeneration,
      ),
    );
  }

  @override
  Stream<IsolationEvent> get isolation => isolationController.stream;

  @override
  Future<void> openIsolationSettings() async {
    openIsolationSettingsCalls++;
  }

  @override
  Future<void> flushPlayback() async {
    flushPlaybackCalls++;
    played.clear();
  }

  @override
  Stream<CoverageHint> get pathCoverage => pathCoverageController.stream;

  @override
  Stream<AudioFocusState> get audioFocus => audioFocusController.stream;

  @override
  Stream<OsRouteChange> get osRouteChanges => osRouteController.stream;

  /// Camera permission [requestCameraPermission] returns.
  CameraPermission cameraPermission;

  /// Current camera catalog.
  List<CameraEndpoint> cameras;

  /// How many times [requestCameraPermission] ran.
  int cameraPermissionRequests = 0;

  /// How many times [startCameraNative] ran.
  int startCameraCalls = 0;

  /// How many times [stopCameraNative] ran.
  int stopCameraCalls = 0;

  /// Whether the camera graph is running.
  bool cameraRunning = false;

  /// Whether the camera is enabled (not Camera-off).
  bool cameraEnabled = true;

  /// Whether Mute-video is substituting black frames.
  bool muteVideo = false;

  /// Selected camera id.
  String? selectedCameraId;

  VideoSurface? _lastVideoSurface;
  VideoFormat? _lastNativeVideoFormat;

  @override
  VideoSurface? get lastVideoSurface => _lastVideoSurface;

  @override
  VideoFormat? get lastNativeVideoFormat => _lastNativeVideoFormat;

  @override
  Future<List<CameraEndpoint>> enumerateCameras() async =>
      List<CameraEndpoint>.of(cameras);

  @override
  Future<CameraPermission> requestCameraPermission() async {
    cameraPermissionRequests++;
    return cameraPermission;
  }

  @override
  Future<NativeGraphStart> startCameraNative({
    String? cameraId,
    VideoFormat? videoFormat,
    bool enabled = true,
    bool muted = false,
  }) async {
    startCameraCalls++;
    if (cameraPermission != CameraPermission.granted) {
      cameraRunning = false;
      _lastVideoSurface = null;
      _lastNativeVideoFormat = null;
      return NativeGraphStart.unavailable;
    }
    final resolved = cameras.where((camera) => camera.id == cameraId).firstOrNull ??
        cameras.firstOrNull;
    if (resolved == null) {
      cameraRunning = false;
      _lastVideoSurface = null;
      _lastNativeVideoFormat = null;
      return NativeGraphStart.unavailable;
    }
    selectedCameraId = resolved.id;
    cameraEnabled = enabled;
    muteVideo = muted;
    cameraRunning = enabled;
    const negotiator = VideoFormatNegotiator();
    _lastNativeVideoFormat = negotiator.nearest(
      videoFormat ?? VideoFormat.defaultFormat,
      resolved.modes.isEmpty ? const [VideoFormat.defaultFormat] : resolved.modes,
    );
    _lastVideoSurface = cameraRunning
        ? const VideoSurface(handle: 1)
        : null;
    return NativeGraphStart.started;
  }

  @override
  Future<void> stopCameraNative() async {
    stopCameraCalls++;
    cameraRunning = false;
    _lastVideoSurface = null;
  }

  @override
  Future<void> selectCameraNative(String cameraId) async {
    selectedCameraId = cameraId;
  }

  @override
  Future<void> setCameraEnabledNative(bool enabled) async {
    cameraEnabled = enabled;
    cameraRunning = enabled;
    _lastVideoSurface = enabled ? const VideoSurface(handle: 1) : null;
  }

  @override
  Future<void> setMuteVideoNative(bool muted) async {
    muteVideo = muted;
  }

  /// Closes injected controllers. Tests only.
  Future<void> dispose() async {
    await captureController.close();
    await isolationController.close();
    await catalogController.close();
    await pathCoverageController.close();
    await audioFocusController.close();
    await osRouteController.close();
  }
}
