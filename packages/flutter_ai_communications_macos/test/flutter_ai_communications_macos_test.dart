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

  test('built-in speakers pair as speakerphone from transport bltn', () {
    expect(
      macosRouteClass(name: 'MacBook Pro Microphone', transport: 'bltn'),
      RouteClass.speakerphone,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.speakerphone,
        id: 'BuiltInMicrophoneDevice',
        name: 'MacBook Pro Microphone',
        uid: 'BuiltInMicrophoneDevice',
        transport: 'bltn',
      ),
      macosBuiltInPairId,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.speakerphone,
        id: 'BuiltInSpeakerDevice',
        name: 'MacBook Pro Speakers',
        uid: 'BuiltInSpeakerDevice',
        transport: 'bltn',
      ),
      macosBuiltInPairId,
    );
  });

  test('built-in speakers pair as speakerphone from transport pci (#96 #97)', () {
    expect(
      macosRouteClass(name: 'Built-in Microphone', transport: 'pci'),
      RouteClass.speakerphone,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.speakerphone,
        id: 'AppleHDAEngineInput:1',
        name: 'Built-in Microphone',
        uid: 'AppleHDAEngineInput:1',
        transport: 'pci',
      ),
      macosBuiltInPairId,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.speakerphone,
        id: 'AppleHDAEngineOutput:1',
        name: 'Built-in Output',
        uid: 'AppleHDAEngineOutput:1',
        transport: 'pci',
      ),
      macosBuiltInPairId,
    );
  });

  test('USB name containing speaker stays wired, not built-in', () {
    expect(
      macosRouteClass(name: 'USB Audio Speakers', transport: 'usb '),
      RouteClass.wired,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.wired,
        id: 'AppleUSBAudioEngine:Generic:USB Audio:1141200:1',
        name: 'USB Audio Speakers',
        uid: 'AppleUSBAudioEngine:Generic:USB Audio:1141200:1',
        transport: 'usb ',
        relatedUids: const [
          'AppleUSBAudioEngine:Generic:USB Audio:1141200:1',
          'AppleUSBAudioEngine:Generic:USB Audio:1141200:2',
        ],
      ),
      'AppleUSBAudioEngine:Generic:USB Audio:1141200:1|'
      'AppleUSBAudioEngine:Generic:USB Audio:1141200:2',
    );
  });

  test('unrelated USB devices with the same name stay separate', () {
    expect(
      macosPairId(
        routeClass: RouteClass.wired,
        id: 'dock-a:3',
        name: 'USB Audio',
        uid: 'dock-a:3',
        transport: 'usb ',
        relatedUids: const ['dock-a:3', 'dock-a:4'],
      ),
      isNot(
        macosPairId(
          routeClass: RouteClass.wired,
          id: 'dock-b:3',
          name: 'USB Audio',
          uid: 'dock-b:3',
          transport: 'usb ',
          relatedUids: const ['dock-b:3', 'dock-b:4'],
        ),
      ),
    );
  });

  test('Bluetooth input and output UIDs share the address Pair identity', () {
    expect(
      macosPairId(
        routeClass: RouteClass.bluetooth,
        id: 'F3-A2-14-A9-1D-F8:input',
        name: 'AirPods Microphone',
        uid: 'F3-A2-14-A9-1D-F8:input',
        transport: 'blue',
      ),
      'F3-A2-14-A9-1D-F8',
    );
    expect(
      macosPairId(
        routeClass: RouteClass.bluetooth,
        id: 'F3-A2-14-A9-1D-F8:output',
        name: 'AirPods',
        uid: 'F3-A2-14-A9-1D-F8:output',
        transport: 'blue',
      ),
      'F3-A2-14-A9-1D-F8',
    );
  });

  test('Bluetooth and USB headsets keep their RouteClass', () {
    expect(
      macosRouteClass(name: 'AirPods', transport: 'blue'),
      RouteClass.bluetooth,
    );
    expect(
      macosRouteClass(name: 'AirPods', transport: 'blea'),
      RouteClass.bluetooth,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.bluetooth,
        id: 'AA:BB:input',
        name: 'AirPods',
        uid: 'F3-A2-14-A9-1D-F8:input',
        transport: 'blea',
      ),
      'F3-A2-14-A9-1D-F8',
    );
    expect(
      macosRouteClass(name: 'USB Headset', transport: 'usb'),
      RouteClass.wired,
    );
  });

  test('virtual and aggregate Core Audio devices stay out of the catalog', () {
    expect(
      macosIsCatalogEndpoint(name: 'Microsoft Teams Audio', transport: 'virt'),
      isFalse,
    );
    expect(
      macosIsCatalogEndpoint(
        name: 'CADDefaultDeviceAggregate',
        transport: 'grup',
      ),
      isFalse,
    );
    expect(
      macosIsCatalogEndpoint(name: 'Device Aggregate', transport: 'fgrp'),
      isFalse,
    );
    expect(
      macosIsCatalogEndpoint(name: 'Device Aggregate', transport: 'auto'),
      isFalse,
    );
    expect(
      macosIsCatalogEndpoint(name: 'Microsoft Teams Audio', transport: ''),
      isFalse,
    );
    expect(
      macosIsCatalogEndpoint(name: 'CADDefaultDeviceAggregate', transport: ''),
      isFalse,
    );
    expect(
      macosIsCatalogEndpoint(name: 'MacBook Pro Speakers', hidden: true),
      isFalse,
    );
  });

  test('physical Core Audio devices stay in the catalog', () {
    expect(
      macosIsCatalogEndpoint(name: 'MacBook Pro Speakers', transport: 'bltn'),
      isTrue,
    );
    expect(
      macosIsCatalogEndpoint(name: 'Realtek USB2.0 Audio', transport: 'usb'),
      isTrue,
    );
    expect(macosIsCatalogEndpoint(name: 'AirPods', transport: 'blue'), isTrue);
    expect(
      macosIsCatalogEndpoint(name: 'DELL U3219Q', transport: 'dprt'),
      isTrue,
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

final class _RecordingBackend with DeviceWatchSupport implements AudioBackend {
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
