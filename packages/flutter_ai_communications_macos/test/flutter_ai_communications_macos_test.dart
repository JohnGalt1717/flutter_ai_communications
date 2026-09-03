import 'dart:typed_data';

import 'package:flutter_ai_communications_macos/flutter_ai_communications_macos.dart';
import 'package:flutter_ai_communications_macos/src/audio_backend.dart';
import 'package:flutter_ai_communications_macos/src/macos_voice_processing_policy.dart';
import 'package:flutter_ai_communications_macos/src/route_class.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS adapter registers and names itself macos', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsMacos.registerWith();
    expect(
      FlutterAiCommunicationsPlatform.instance,
      isA<FlutterAiCommunicationsMacos>(),
    );
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'macos');
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('macOS Isolation is unavailable', () {
    final adapter = FlutterAiCommunicationsMacos(backend: _RecordingBackend());
    expect(adapter.lastIsolation.state, IsolationState.unavailable);
  });

  test('macOS duplex policy keeps capture and playback on one engine', () {
    expect(MacosVoiceProcessingPolicy.usesSingleDuplexEngine, isTrue);
    expect(MacosVoiceProcessingPolicy.playbackMustShareCaptureEngine, isTrue);
    expect(
      MacosVoiceProcessingPolicy.mixerMustConnectToOutputOnSameEngine,
      isTrue,
    );
    expect(MacosVoiceProcessingPolicy.isolationState, 'unavailable');
  });

  test('capture-only does not attach playback', () {
    expect(MacosVoiceProcessingPolicy.wantsCapture('usb-in', null), isTrue);
    expect(MacosVoiceProcessingPolicy.wantsPlayback('usb-in', null), isFalse);
  });

  test('playback-only does not attach capture', () {
    expect(MacosVoiceProcessingPolicy.wantsCapture(null, 'usb-out'), isFalse);
    expect(MacosVoiceProcessingPolicy.wantsPlayback(null, 'usb-out'), isTrue);
  });

  test('built-in speakers pair as speakerphone', () {
    expect(
      macosRouteClass(name: 'MacBook Pro Microphone', transport: 'bltn'),
      RouteClass.speakerphone,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.speakerphone,
        id: 'id',
        name: 'Speakers',
      ),
      macosBuiltInPairId,
    );
  });

  test('AirPods capture and render share one Pair identity', () {
    expect(
      macosPairId(
        routeClass: RouteClass.bluetooth,
        id: 'HFP-UID',
        name: 'AirPods Microphone',
        uid: 'HFP-UID',
      ),
      macosPairId(
        routeClass: RouteClass.bluetooth,
        id: 'A2DP-UID',
        name: 'AirPods',
        uid: 'A2DP-UID',
      ),
    );
  });

  test('Bluetooth and USB headsets keep their RouteClass', () {
    expect(
      macosRouteClass(name: 'AirPods', transport: 'blue'),
      RouteClass.bluetooth,
    );
    expect(
      macosRouteClass(name: 'USB Headset', transport: 'usb'),
      RouteClass.wired,
    );
  });

  test('start and select report Observed from bound native devices', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsMacos(backend: backend);
    final seen = <OsRouteChange>[];
    final sub = adapter.osRouteChanges.listen(seen.add);
    addTearDown(() async {
      await sub.cancel();
      await adapter.stopNative();
    });

    expect(adapter.lastObservedRoute.captureId, isNull);
    expect(adapter.lastObservedRoute.renderId, isNull);

    final started = await adapter.startNative(
      captureId: 'usb-in',
      renderId: 'usb-out',
    );
    expect(started, NativeGraphStart.started);
    expect(adapter.lastObservedRoute.captureId, 'usb-in');
    expect(adapter.lastObservedRoute.renderId, 'usb-out');
    expect(seen, isNotEmpty);
    expect(seen.last.captureId, 'usb-in');
    expect(seen.last.renderId, 'usb-out');
    expect(seen.last.generation, isNotNull);

    await adapter.selectEndpoints(
      captureId: 'built-in-in',
      renderId: 'built-in-out',
    );
    expect(adapter.lastObservedRoute.captureId, 'built-in-in');
    expect(adapter.lastObservedRoute.renderId, 'built-in-out');
    expect(seen.last.captureId, 'built-in-in');
    expect(seen.last.renderId, 'built-in-out');

    await adapter.selectEndpoints(captureId: 'usb-in', renderId: 'usb-out');
    expect(adapter.lastObservedRoute.captureId, 'usb-in');
    expect(adapter.lastObservedRoute.renderId, 'usb-out');
    expect(seen.last.captureId, 'usb-in');
    expect(seen.last.renderId, 'usb-out');
  });

  test('capture-only start does not bind render', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsMacos(backend: backend);
    addTearDown(adapter.stopNative);

    final started = await adapter.startNative(captureId: 'usb-in');
    expect(started, NativeGraphStart.started);
    expect(adapter.lastObservedRoute.captureId, 'usb-in');
    expect(adapter.lastObservedRoute.renderId, isNull);
  });

  test('playback-only start does not bind capture', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsMacos(backend: backend);
    addTearDown(adapter.stopNative);

    final started = await adapter.startNative(renderId: 'usb-out');
    expect(started, NativeGraphStart.started);
    expect(adapter.lastObservedRoute.captureId, isNull);
    expect(adapter.lastObservedRoute.renderId, 'usb-out');
  });

  test('bind failure does not report the requested UID', () async {
    final backend = _RecordingBackend()..failBind = true;
    final adapter = FlutterAiCommunicationsMacos(backend: backend);
    addTearDown(adapter.stopNative);

    final started = await adapter.startNative(
      captureId: 'usb-in',
      renderId: 'usb-out',
    );
    expect(started, NativeGraphStart.failed);
    expect(adapter.lastObservedRoute.captureId, isNot('usb-in'));
    expect(adapter.lastObservedRoute.renderId, isNot('usb-out'));
  });
}

final class _RecordingBackend implements AudioBackend {
  PairingSnapshot bound = const PairingSnapshot();
  var failBind = false;

  @override
  List<Endpoint> enumerate() => const [
    Endpoint(
      id: 'usb-in',
      name: 'USB Audio',
      routeClass: RouteClass.wired,
      isCapture: true,
      pairId: 'usb',
    ),
    Endpoint(
      id: 'usb-out',
      name: 'USB Audio',
      routeClass: RouteClass.wired,
      isCapture: false,
      pairId: 'usb',
    ),
    Endpoint(
      id: 'built-in-in',
      name: 'MacBook Pro Microphone',
      routeClass: RouteClass.speakerphone,
      isCapture: true,
      pairId: macosBuiltInPairId,
    ),
    Endpoint(
      id: 'built-in-out',
      name: 'MacBook Pro Speakers',
      routeClass: RouteClass.speakerphone,
      isCapture: false,
      pairId: macosBuiltInPairId,
    ),
  ];

  @override
  MicrophonePermission probePermission() => MicrophonePermission.granted;

  @override
  NativeGraphStart start({
    String? captureId,
    String? renderId,
    bool noiseCancelling = true,
  }) {
    if (failBind) {
      bound = const PairingSnapshot();
      return NativeGraphStart.failed;
    }
    final capture = captureId == null || captureId.isEmpty ? null : captureId;
    final render = renderId == null || renderId.isEmpty ? null : renderId;
    final wantCapture = capture != null || render == null;
    final wantRender = render != null || capture == null;
    bound = PairingSnapshot(
      captureId: wantCapture ? capture ?? 'built-in-in' : null,
      renderId: wantRender ? render ?? 'built-in-out' : null,
    );
    return NativeGraphStart.started;
  }

  @override
  void stop() {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void play(Uint8List bytes) {}

  @override
  void select({String? captureId, String? renderId}) {
    bound = PairingSnapshot(
      captureId: captureId ?? bound.captureId,
      renderId: renderId ?? bound.renderId,
    );
  }

  @override
  PairingSnapshot get observed => bound;

  @override
  void flush() {}

  @override
  Stream<Uint8List> get capture => const Stream.empty();

  @override
  void dispose() {}
}
