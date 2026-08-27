import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ai_communications_linux/flutter_ai_communications_linux.dart';
import 'package:flutter_ai_communications_linux/src/audio_backend.dart';
import 'package:flutter_ai_communications_linux/src/linux_bluetooth_identity.dart';
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

  test('Pulse car form_factor is a car RouteClass', () {
    expect(
      linuxRouteClass(name: 'bluez_sink', bus: 'bluetooth', formFactor: 'car'),
      RouteClass.car,
    );
    expect(linuxEndpointFormFactor('car'), EndpointFormFactor.car);
    expect(linuxEndpointFormFactor('headset'), EndpointFormFactor.headset);
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

  test('WSLg RDP devices pair as speakerphone', () {
    expect(
      linuxRouteClass(name: 'RDP Source', bus: ''),
      RouteClass.speakerphone,
    );
    expect(linuxRouteClass(name: 'RDP Sink', bus: ''), RouteClass.speakerphone);
  });

  test('Pulse form_factor and bus fill RouteClass and form factor', () {
    final tesla = linuxEndpointFromPulse(
      id: 'bluez_sink.aa_bb_cc_dd_ee_ff.a2dp_sink',
      name: 'bluez_sink',
      isCapture: false,
      bus: 'bluetooth',
      formFactor: 'car',
      card: 12,
    );
    expect(tesla.routeClass, RouteClass.car);
    expect(tesla.capabilities.formFactor, EndpointFormFactor.car);
    expect(tesla.capabilities.carConnected, isTrue);
    expect(tesla.pairId, 'card-12');
  });

  test(
    'permission probe uses the backend and does not start a Session',
    () async {
      final backend = _RecordingBackend();
      final adapter = FlutterAiCommunicationsLinux(backend: backend);
      addTearDown(adapter.stopNative);
      expect(
        await adapter.requestMicrophonePermission(),
        MicrophonePermission.granted,
      );
      expect(backend.started, isFalse);
    },
  );

  test('failed BlueZ identity leaves Pulse names', () async {
    final source = BlueZBluetoothIdentitySource(
      enumerate: () async => throw StateError('no bluetoothd'),
    );
    await source.prepare();
    expect(source.current(), isEmpty);
  });

  test('Bluetooth identity enriches matching Endpoints', () async {
    final backend = _BluetoothBackend();
    final adapter = FlutterAiCommunicationsLinux(
      backend: backend,
      bluetooth: _FixedBluetoothSource(const [
        BluetoothIdentity(
          name: 'Tesla Model Y',
          classOfDevice: 0x420,
          hints: ['Tesla'],
        ),
      ]),
    );
    addTearDown(adapter.stopNative);
    final catalog = await adapter.enumerateEndpoints();
    final tesla = catalog.firstWhere((endpoint) => endpoint.id == 'bt-in');
    expect(tesla.identityHints, ['Tesla Model Y', 'Tesla']);
    expect(tesla.capabilities.formFactor, EndpointFormFactor.car);
  });

  test('car Class of Device is a car form factor', () {
    expect(linuxFormFactorFromClassOfDevice(0x420), EndpointFormFactor.car);
  });

  test(
    'BlueZ busctl snapshot maps Class of Device and manufacturer data',
    () async {
      Future<ProcessResult> run(List<String> args) async {
        if (args.contains('tree')) {
          return ProcessResult(
            0,
            0,
            '/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6\n',
            '',
          );
        }
        return ProcessResult(
          0,
          0,
          's "Tesla Model Y"\n'
              's "Tesla Model Y"\n'
              's "A1:B2:C3:D4:E5:F6"\n'
              'u 1056\n'
              'a{qv} { 301 <[ay 2 0x2d 0x01]> }\n',
          '',
        );
      }

      final devices = await enumerateBluezDevices(runBusctl: run);
      expect(devices, hasLength(1));
      expect(devices.single.name, 'Tesla Model Y');
      expect(devices.single.classOfDevice, 0x420);
      expect(devices.single.address, 'A1:B2:C3:D4:E5:F6');
      expect(devices.single.hints, ['Sony']);
    },
  );

  test('ManufacturerData company ids map to brand hints', () {
    expect(manufacturerHintFromCompanyId(0x012D), 'Sony');
    expect(manufacturerHintFromCompanyId(0x004C), 'Apple');
    expect(manufacturerHintFromCompanyId(0x00E0), 'Google');
    expect(manufacturerHintFromCompanyId(0x1), isNull);
    expect(
      parseBluezManufacturerCompanyIds(
        'a{qv} { 301 <[ay 4 0x2d 0x01 0x01 0x00]> 76 <[ay 2 0x4c 0x00]> }',
      ),
      [301, 76],
    );
    expect(parseBusctlString('s "Tesla Model Y"'), 'Tesla Model Y');
    expect(parseBusctlUint('u 1056'), 1056);
  });

  test('enumerate retries when Pulse catalog is briefly empty', () async {
    final backend = _FlakyCatalogBackend();
    final adapter = FlutterAiCommunicationsLinux(backend: backend);
    addTearDown(adapter.stopNative);
    final catalog = await adapter.enumerateEndpoints();
    expect(catalog.map((endpoint) => endpoint.id), contains('usb-in'));
    expect(backend.enumerateCalls, greaterThan(1));
  });

  test('endpoint catalog emits before startNative', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsLinux(backend: backend);
    addTearDown(adapter.stopNative);
    final seen = <List<Endpoint>>[];
    final sub = adapter.endpointCatalog.listen(seen.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isNotEmpty);
    expect(seen.first.map((endpoint) => endpoint.id), contains('usb-in'));
  });

  test(
    'startNative keeps catalog available without a prior subscriber',
    () async {
      final backend = _RecordingBackend();
      final adapter = FlutterAiCommunicationsLinux(backend: backend);
      addTearDown(adapter.stopNative);
      expect(
        await adapter.startNative(captureId: 'usb-in', renderId: 'usb-out'),
        NativeGraphStart.started,
      );
      final seen = <List<Endpoint>>[];
      final sub = adapter.endpointCatalog.listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isNotEmpty);
      expect(seen.first.map((endpoint) => endpoint.id), contains('usb-in'));
    },
  );
}

final class _RecordingBackend implements AudioBackend {
  PairingSnapshot bound = const PairingSnapshot();
  var started = false;

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
    started = true;
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

final class _FlakyCatalogBackend implements AudioBackend {
  final _RecordingBackend _inner = _RecordingBackend();
  var enumerateCalls = 0;

  @override
  List<Endpoint> enumerate() {
    enumerateCalls++;
    if (enumerateCalls < 3) {
      return const [];
    }
    return _inner.enumerate();
  }

  @override
  MicrophonePermission probePermission() => _inner.probePermission();

  @override
  NativeGraphStart start({String? captureId, String? renderId}) =>
      _inner.start(captureId: captureId, renderId: renderId);

  @override
  void stop() => _inner.stop();

  @override
  void pause() => _inner.pause();

  @override
  void resume() => _inner.resume();

  @override
  void play(Uint8List bytes) => _inner.play(bytes);

  @override
  void select({String? captureId, String? renderId}) =>
      _inner.select(captureId: captureId, renderId: renderId);

  @override
  PairingSnapshot get observed => _inner.observed;

  @override
  void flush() => _inner.flush();

  @override
  Stream<Uint8List> get capture => _inner.capture;

  @override
  void dispose() => _inner.dispose();
}

final class _FixedBluetoothSource implements BluetoothIdentitySource {
  _FixedBluetoothSource(this._devices);

  final List<BluetoothIdentity> _devices;

  @override
  List<BluetoothIdentity> current() => _devices;

  @override
  Future<void> prepare() async {}
}

final class _BluetoothBackend implements AudioBackend {
  final _RecordingBackend _inner = _RecordingBackend();

  @override
  List<Endpoint> enumerate() => [
    ..._inner.enumerate(),
    const Endpoint(
      id: 'bt-in',
      name: 'Headphones (Tesla Model Y)',
      routeClass: RouteClass.bluetooth,
      isCapture: true,
      pairId: 'bt',
    ),
    const Endpoint(
      id: 'bt-out',
      name: 'Headphones (Tesla Model Y)',
      routeClass: RouteClass.bluetooth,
      isCapture: false,
      pairId: 'bt',
    ),
  ];

  @override
  MicrophonePermission probePermission() => _inner.probePermission();

  @override
  NativeGraphStart start({String? captureId, String? renderId}) =>
      _inner.start(captureId: captureId, renderId: renderId);

  @override
  void stop() => _inner.stop();

  @override
  void pause() => _inner.pause();

  @override
  void resume() => _inner.resume();

  @override
  void play(Uint8List bytes) => _inner.play(bytes);

  @override
  void select({String? captureId, String? renderId}) =>
      _inner.select(captureId: captureId, renderId: renderId);

  @override
  PairingSnapshot get observed => _inner.observed;

  @override
  void flush() => _inner.flush();

  @override
  Stream<Uint8List> get capture => _inner.capture;

  @override
  void dispose() => _inner.dispose();
}
