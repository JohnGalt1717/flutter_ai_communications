import 'dart:typed_data';

import 'package:flutter_ai_communications_linux/flutter_ai_communications_linux.dart';
import 'package:flutter_ai_communications_linux/src/audio_backend.dart';
import 'package:flutter_ai_communications_linux/src/route_class.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux adapter registers and names itself linux', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsLinux.registerWith();
    expect(
      FlutterAiCommunicationsPlatform.instance,
      isA<FlutterAiCommunicationsLinux>(),
    );
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'linux');
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('Linux Isolation is unavailable', () {
    final adapter = FlutterAiCommunicationsLinux();
    expect(adapter.lastIsolation.state, IsolationState.unavailable);
  });

  test('built-in analog devices pair as speakerphone', () {
    expect(
      linuxRouteClass(name: 'Built-in Audio Analog Stereo', bus: 'pci'),
      RouteClass.speakerphone,
    );
    expect(
      linuxPairId(
        routeClass: RouteClass.speakerphone,
        id: 'alsa_output.pci',
        name: 'Built-in Audio',
      ),
      linuxBuiltInPairId,
    );
  });

  test('Bluetooth and USB headsets keep their RouteClass', () {
    expect(
      linuxRouteClass(name: 'WH-1000XM5', bus: 'bluetooth'),
      RouteClass.bluetooth,
    );
    expect(
      linuxRouteClass(name: 'USB Headset', bus: 'usb', formFactor: 'headset'),
      RouteClass.wired,
    );
  });

  test('start and select report Observed from bound native devices', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsLinux(backend: backend);
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
  });
}

final class _RecordingBackend implements AudioBackend {
  PairingSnapshot bound = const PairingSnapshot();

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
      name: 'Built-in Audio Analog Stereo',
      routeClass: RouteClass.speakerphone,
      isCapture: true,
      pairId: linuxBuiltInPairId,
    ),
    Endpoint(
      id: 'built-in-out',
      name: 'Built-in Audio Analog Stereo',
      routeClass: RouteClass.speakerphone,
      isCapture: false,
      pairId: linuxBuiltInPairId,
    ),
  ];

  @override
  MicrophonePermission probePermission() => MicrophonePermission.granted;

  @override
  NativeGraphStart start({String? captureId, String? renderId}) {
    bound = PairingSnapshot(
      captureId: captureId ?? 'built-in-in',
      renderId: renderId ?? 'built-in-out',
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
