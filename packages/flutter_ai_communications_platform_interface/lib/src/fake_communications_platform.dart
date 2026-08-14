import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

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
    this.nativeStart = NativeGraphStart.started,
    List<Endpoint>? catalog,
  }) : catalog = List<Endpoint>.of(catalog ?? defaultCatalog);

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

  /// How many times [openIsolationSettings] ran.
  int openIsolationSettingsCalls = 0;

  /// How many times [flushPlayback] ran.
  int flushPlaybackCalls = 0;

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
  Future<MicrophonePermission> requestMicrophonePermission() async =>
      permission;

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
  }) async {
    startNativeCalls++;
    final error = startNativeError;
    if (error != null) {
      throw error;
    }
    if (nativeStart != NativeGraphStart.started) {
      return nativeStart;
    }
    selectedCaptureId =
        captureId ??
        catalog.where((endpoint) => endpoint.isCapture).firstOrNull?.id;
    selectedRenderId =
        renderId ??
        catalog.where((endpoint) => !endpoint.isCapture).firstOrNull?.id;
    nativeRunning = true;
    nativePaused = false;
    lastIsolationEvent = const IsolationEvent(IsolationState.off);
    isolationController.add(lastIsolationEvent);
    return NativeGraphStart.started;
  }

  @override
  Future<void> stopNative() async {
    nativeRunning = false;
    nativePaused = false;
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
    if (captureId != null) {
      selectedCaptureId = captureId;
    }
    if (renderId != null) {
      selectedRenderId = renderId;
    }
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
