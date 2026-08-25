import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_windows/flutter_ai_communications_windows.dart';
import 'package:flutter_ai_communications_windows/src/route_class.dart';
import 'package:flutter_ai_communications_windows/src/wasapi_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows adapter registers and names itself windows', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsWindows.registerWith();
    expect(
      FlutterAiCommunicationsPlatform.instance,
      isA<FlutterAiCommunicationsWindows>(),
    );
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'windows');
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('Windows Isolation is unavailable', () {
    final adapter = FlutterAiCommunicationsWindows();
    expect(adapter.lastIsolation.state, IsolationState.unavailable);
  });

  test('built-in speakers pair as speakerphone', () {
    expect(
      windowsRouteClass(name: 'Speakers (Realtek)', enumerator: 'HDAUDIO'),
      RouteClass.speakerphone,
    );
    expect(
      windowsPairId(
        routeClass: RouteClass.speakerphone,
        id: 'id',
        name: 'Speakers',
      ),
      windowsBuiltInPairId,
    );
  });

  test('Bluetooth and USB headsets keep their RouteClass', () {
    expect(
      windowsRouteClass(name: 'AirPods', enumerator: 'BTHENUM'),
      RouteClass.bluetooth,
    );
    expect(
      windowsRouteClass(name: 'USB Headset', enumerator: 'USB'),
      RouteClass.wired,
    );
  });

  test('webcam capture is wired, not speakerphone', () {
    expect(
      windowsRouteClass(name: 'Logitech BRIO', enumerator: 'USBVIDEO'),
      RouteClass.wired,
    );
    expect(
      windowsRouteClass(name: 'HD Pro Webcam C920', enumerator: ''),
      RouteClass.wired,
    );
  });

  test('USB capture and render share container Pair identity', () {
    expect(
      windowsPairId(
        routeClass: RouteClass.wired,
        id: 'in',
        name: 'Microphone (USB Audio Device)',
        containerId: '{a0b1c2d3-e4f5-6789-abcd-ef0123456789}',
      ),
      windowsPairId(
        routeClass: RouteClass.wired,
        id: 'out',
        name: 'Speakers (USB Audio Device)',
        containerId: '{a0b1c2d3-e4f5-6789-abcd-ef0123456789}',
      ),
    );
  });

  test('start and select report Observed from bound native devices', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
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

    expect(adapter.lastNativeFormats.capture, AudioFormat.pcm16le24k);
    expect(adapter.lastNativeFormats.playback, AudioFormat.pcm16le24k);

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

  test('bind failure does not report the requested UID', () async {
    final backend = _RecordingBackend()..failBind = true;
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
    addTearDown(adapter.stopNative);

    final started = await adapter.startNative(
      captureId: 'usb-in',
      renderId: 'usb-out',
    );
    expect(started, NativeGraphStart.failed);
    expect(adapter.lastObservedRoute.captureId, isNot('usb-in'));
    expect(adapter.lastObservedRoute.renderId, isNot('usb-out'));
  });

  test('capture-only start does not bind render', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
    addTearDown(adapter.stopNative);

    final started = await adapter.startNative(captureId: 'usb-in');
    expect(started, NativeGraphStart.started);
    expect(adapter.lastObservedRoute.captureId, 'usb-in');
    expect(adapter.lastObservedRoute.renderId, isNull);
    expect(adapter.lastNativeFormats.capture, AudioFormat.pcm16le24k);
    expect(adapter.lastNativeFormats.playback, isNull);
  });

  test('playback-only start does not bind capture', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
    addTearDown(adapter.stopNative);

    final started = await adapter.startNative(renderId: 'usb-out');
    expect(started, NativeGraphStart.started);
    expect(adapter.lastObservedRoute.captureId, isNull);
    expect(adapter.lastObservedRoute.renderId, 'usb-out');
    expect(adapter.lastNativeFormats.capture, isNull);
    expect(adapter.lastNativeFormats.playback, AudioFormat.pcm16le24k);
  });

  test('endpoint catalog emits before startNative', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
    addTearDown(adapter.stopNative);
    final seen = <List<Endpoint>>[];
    final sub = adapter.endpointCatalog.listen(seen.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isNotEmpty);
    expect(seen.first.map((endpoint) => endpoint.id), contains('usb-in'));
  });
}

final class _RecordingBackend implements WasapiBackend {
  PairingSnapshot bound = const PairingSnapshot();
  var failBind = false;

  @override
  List<Endpoint> enumerate() => const [
    Endpoint(
      id: 'usb-in',
      name: 'USB Headset',
      routeClass: RouteClass.wired,
      isCapture: true,
      pairId: 'usb',
    ),
    Endpoint(
      id: 'usb-out',
      name: 'USB Headset',
      routeClass: RouteClass.wired,
      isCapture: false,
      pairId: 'usb',
    ),
    Endpoint(
      id: 'built-in-in',
      name: 'Microphone (Realtek)',
      routeClass: RouteClass.speakerphone,
      isCapture: true,
      pairId: windowsBuiltInPairId,
    ),
    Endpoint(
      id: 'built-in-out',
      name: 'Speakers (Realtek)',
      routeClass: RouteClass.speakerphone,
      isCapture: false,
      pairId: windowsBuiltInPairId,
    ),
  ];

  @override
  MicrophonePermission probePermission() => MicrophonePermission.granted;

  @override
  NativeGraphStart start({String? captureId, String? renderId}) {
    if (failBind) {
      bound = const PairingSnapshot();
      return NativeGraphStart.failed;
    }
    if (captureId == null && renderId == null) {
      bound = const PairingSnapshot(
        captureId: 'built-in-in',
        renderId: 'built-in-out',
      );
    } else {
      bound = PairingSnapshot(captureId: captureId, renderId: renderId);
    }
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
  NativeFormatReport get nativeFormats => NativeFormatReport(
    capture: bound.captureId == null ? null : AudioFormat.pcm16le24k,
    playback: bound.renderId == null ? null : AudioFormat.pcm16le24k,
  );

  @override
  void flush() {}

  @override
  Stream<Uint8List> get capture => const Stream.empty();

  @override
  void dispose() {}
}
