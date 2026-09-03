import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'camera_permission.dart';
import 'flutter_ai_communications_platform.dart';
import 'isolation.dart';
import 'microphone_permission.dart';
import 'native_graph_start.dart';
import 'platform_events.dart';
import 'screen_permission.dart';

/// In-memory adapter for tests. Does not touch a real device.
final class FakeCommunicationsPlatform extends FlutterAiCommunicationsPlatform {
  /// Creates a fake adapter.
  FakeCommunicationsPlatform({
    this.permission = MicrophonePermission.granted,
    this.cameraPermission = CameraPermission.granted,
    this.screenPermission = ScreenPermission.granted,
    this.nativeStart = NativeGraphStart.started,
    List<Endpoint>? catalog,
    List<CameraEndpoint>? cameras,
    List<ScreenSource>? screenSources,
  }) : catalog = List<Endpoint>.of(catalog ?? defaultCatalog),
       cameras = List<CameraEndpoint>.of(cameras ?? defaultCameras),
       screenSources = List<ScreenSource>.of(
         screenSources ?? defaultScreenSources,
       );

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

  /// Built-in display, window, All-displays, and system-picker sources.
  static const List<ScreenSource> defaultScreenSources = [
    ScreenSource(
      id: 'display-0',
      name: 'Display 1',
      kind: ScreenSourceKind.display,
      width: 1920,
      height: 1080,
      canPreview: true,
    ),
    ScreenSource(
      id: 'window-notepad',
      name: 'Notepad',
      kind: ScreenSourceKind.window,
      width: 800,
      height: 600,
      canPreview: true,
    ),
    ScreenSource(
      id: 'all-displays',
      name: 'All displays',
      kind: ScreenSourceKind.allDisplays,
      width: 1920,
      height: 1080,
      canPreview: true,
    ),
    ScreenSource(
      id: 'system-picker',
      name: 'System picker',
      kind: ScreenSourceKind.systemPicker,
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

  var _cameraFrameCount = 0;
  var _cameraLiveFrames = 0;

  @override
  int get lastCameraFrameCount => _cameraFrameCount;

  @override
  int get lastCameraLiveFrames => _cameraLiveFrames;

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
    _cameraFrameCount = cameraRunning ? 8 : 0;
    _cameraLiveFrames = cameraRunning && !muted ? 8 : 0;
    return NativeGraphStart.started;
  }

  @override
  Future<void> stopCameraNative() async {
    stopCameraCalls++;
    cameraRunning = false;
    _lastVideoSurface = null;
    _cameraFrameCount = 0;
    _cameraLiveFrames = 0;
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
    if (muted) {
      _cameraLiveFrames = 0;
    }
  }

  @override
  Future<void> pollCameraNative() async {
    if (cameraRunning && !muteVideo) {
      _cameraFrameCount += 4;
      _cameraLiveFrames += 4;
    } else if (cameraRunning) {
      _cameraFrameCount += 4;
    }
  }

  /// Screen permission [requestScreenPermission] returns.
  ScreenPermission screenPermission;

  /// Current Screen source catalog.
  List<ScreenSource> screenSources;

  /// How many times [requestScreenPermission] ran.
  int screenPermissionRequests = 0;

  /// Whether Screen pick is open.
  bool screenPickOpen = false;

  /// Indicated Screen source id, if any.
  String? indicatedScreenSourceId;

  /// Whether screen send is running.
  bool screenSending = false;

  /// Live Include-sound flag.
  bool includeSystemAudio = false;

  /// Whether the fake can actually loop back system audio.
  bool systemAudioAvailable = true;

  /// Screen motion flag.
  bool screenMotion = false;

  /// Cursor capture flag.
  bool screenCursor = true;

  /// Selected / sending Screen source id.
  String? selectedScreenSourceId;

  /// How many times [startScreenShareNative] ran.
  int startScreenShareCalls = 0;

  final Map<String, VideoSurface> _screenPreviews = {};
  VideoSurface? _lastScreenSurface;
  VideoFormat? _lastScreenNativeFormat;
  String? _lastScreenUnavailableReason;

  /// Catalog updates tests inject.
  final StreamController<List<ScreenSource>> screenCatalogController =
      StreamController<List<ScreenSource>>.broadcast();

  @override
  VideoSurface? get lastScreenSurface => _lastScreenSurface;

  @override
  VideoFormat? get lastScreenNativeFormat => _lastScreenNativeFormat;

  @override
  String? get lastScreenUnavailableReason => _lastScreenUnavailableReason;

  @override
  Future<List<ScreenSource>> enumerateScreenSources() async =>
      List<ScreenSource>.of(screenSources);

  @override
  Stream<List<ScreenSource>> get screenSourceCatalog =>
      screenCatalogController.stream;

  @override
  Future<ScreenPermission> requestScreenPermission() async {
    screenPermissionRequests++;
    return screenPermission;
  }

  @override
  Future<NativeGraphStart> beginScreenPickNative() async {
    if (screenPermission != ScreenPermission.granted) {
      screenPickOpen = true;
      _screenPreviews.clear();
      return NativeGraphStart.unavailable;
    }
    screenPickOpen = true;
    _screenPreviews
      ..clear()
      ..addEntries(
        screenSources.where((source) => source.canPreview).map(
          (source) => MapEntry(
            source.id,
            VideoSurface(handle: 100 + source.id.hashCode.abs() % 50),
          ),
        ),
      );
    return NativeGraphStart.started;
  }

  @override
  Future<void> endScreenPickNative() async {
    screenPickOpen = false;
    _screenPreviews.clear();
    indicatedScreenSourceId = null;
  }

  @override
  Future<void> indicateScreenSourceNative(String? sourceId) async {
    indicatedScreenSourceId = sourceId;
  }

  @override
  VideoSurface? screenPreviewNative(String sourceId) =>
      _screenPreviews[sourceId];

  @override
  Future<NativeGraphStart> startScreenShareNative({
    required String sourceId,
    bool includeSystemAudio = false,
    bool cursor = true,
    bool motion = false,
  }) async {
    startScreenShareCalls++;
    if (screenPermission != ScreenPermission.granted) {
      screenSending = false;
      _lastScreenSurface = null;
      _lastScreenNativeFormat = null;
      _lastScreenUnavailableReason = screenPermission.name;
      return NativeGraphStart.unavailable;
    }
    var id = sourceId;
    if (id == 'system-picker') {
      id = screenSources
              .where((source) => source.kind == ScreenSourceKind.display)
              .firstOrNull
              ?.id ??
          id;
    }
    final source = screenSources.where((item) => item.id == id).firstOrNull;
    if (source == null) {
      screenSending = false;
      _lastScreenSurface = null;
      _lastScreenNativeFormat = null;
      _lastScreenUnavailableReason = 'none';
      return NativeGraphStart.unavailable;
    }
    selectedScreenSourceId = source.id;
    this.includeSystemAudio = includeSystemAudio && systemAudioAvailable;
    screenCursor = cursor;
    screenMotion = motion;
    screenSending = true;
    indicatedScreenSourceId = source.id;
    final requested = ScreenVideoFormat.request(
      width: source.width ?? 1920,
      height: source.height ?? 1080,
      motion: motion,
    );
    _lastScreenNativeFormat = requested;
    _lastScreenSurface = const VideoSurface(handle: 2);
    _lastScreenUnavailableReason = null;
    return NativeGraphStart.started;
  }

  @override
  Future<void> stopScreenShareNative() async {
    screenSending = false;
    selectedScreenSourceId = null;
    includeSystemAudio = false;
    _lastScreenSurface = null;
    _lastScreenNativeFormat = null;
    indicatedScreenSourceId = null;
  }

  @override
  Future<bool> setIncludeSystemAudioNative(bool enabled) async {
    if (!systemAudioAvailable) {
      includeSystemAudio = false;
      return false;
    }
    includeSystemAudio = enabled;
    return enabled;
  }

  @override
  Future<void> setScreenMotionNative(bool motion) async {
    screenMotion = motion;
  }

  @override
  Future<void> setScreenCursorNative(bool cursor) async {
    screenCursor = cursor;
  }

  /// Closes injected controllers. Tests only.
  Future<void> dispose() async {
    await captureController.close();
    await isolationController.close();
    await catalogController.close();
    await pathCoverageController.close();
    await audioFocusController.close();
    await osRouteController.close();
    await screenCatalogController.close();
  }
}
