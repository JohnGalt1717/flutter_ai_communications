import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_windows/flutter_ai_communications_windows.dart';
import 'package:flutter_ai_communications_windows/src/route_class.dart';
import 'package:flutter_ai_communications_windows/src/wasapi_backend.dart';
import 'package:flutter_ai_communications_windows/src/windows_bluetooth_identity.dart';
import 'package:flutter_ai_communications_windows/src/windows_microphone_consent.dart';
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

  test('denied Store consent is denied without opening WASAPI', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(
      backend: backend,
      consent: _FixedConsent(MicrophonePermission.denied),
    );
    addTearDown(adapter.stopNative);
    expect(
      await adapter.requestMicrophonePermission(),
      MicrophonePermission.denied,
    );
    expect(backend.probeCalls, 0);
  });

  test(
    'restricted Store consent is restricted without opening WASAPI',
    () async {
      final backend = _RecordingBackend();
      final adapter = FlutterAiCommunicationsWindows(
        backend: backend,
        consent: _FixedConsent(MicrophonePermission.restricted),
      );
      addTearDown(adapter.stopNative);
      expect(
        await adapter.requestMicrophonePermission(),
        MicrophonePermission.restricted,
      );
      expect(backend.probeCalls, 0);
    },
  );

  test('DeviceAccessStatus maps to MicrophonePermission', () {
    expect(permissionFromDeviceAccessStatus(1), MicrophonePermission.granted);
    expect(permissionFromDeviceAccessStatus(2), MicrophonePermission.denied);
    expect(
      permissionFromDeviceAccessStatus(3),
      MicrophonePermission.restricted,
    );
    expect(permissionFromDeviceAccessStatus(0), isNull);
  });

  test('AppCapabilityAccessStatus maps to MicrophonePermission', () {
    expect(permissionFromAppCapabilityStatus(4), MicrophonePermission.granted);
    expect(permissionFromAppCapabilityStatus(2), MicrophonePermission.denied);
    expect(permissionFromAppCapabilityStatus(1), MicrophonePermission.denied);
    expect(
      permissionFromAppCapabilityStatus(0),
      MicrophonePermission.restricted,
    );
    expect(permissionFromAppCapabilityStatus(3), isNull);
  });

  test('unpackaged Win32 skips Store consent and probes WASAPI', () async {
    final backend = _RecordingBackend();
    final packaged = _RecordingConsent();
    final adapter = FlutterAiCommunicationsWindows(
      backend: backend,
      consent: GatedWindowsMicrophoneConsent(
        isPackaged: () => false,
        packaged: packaged,
      ),
    );
    addTearDown(adapter.stopNative);
    expect(
      await adapter.requestMicrophonePermission(),
      MicrophonePermission.granted,
    );
    expect(packaged.calls, 0);
    expect(backend.probeCalls, 1);
  });

  test('packaged Store host requests consent before WASAPI probe', () async {
    final backend = _RecordingBackend();
    final packaged = _RecordingConsent()..result = MicrophonePermission.denied;
    final adapter = FlutterAiCommunicationsWindows(
      backend: backend,
      consent: GatedWindowsMicrophoneConsent(
        isPackaged: () => true,
        packaged: packaged,
      ),
    );
    addTearDown(adapter.stopNative);
    expect(
      await adapter.requestMicrophonePermission(),
      MicrophonePermission.denied,
    );
    expect(packaged.calls, 1);
    expect(backend.probeCalls, 0);
  });

  test('granted Store consent still probes WASAPI capture', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(
      backend: backend,
      consent: _FixedConsent(MicrophonePermission.granted),
    );
    addTearDown(adapter.stopNative);
    expect(
      await adapter.requestMicrophonePermission(),
      MicrophonePermission.granted,
    );
    expect(backend.probeCalls, 1);
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

  test('empty capture id is treated as playback-only', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
    addTearDown(adapter.stopNative);

    final started = await adapter.startNative(
      captureId: '',
      renderId: 'usb-out',
    );
    expect(started, NativeGraphStart.started);
    expect(adapter.lastObservedRoute.captureId, isNull);
    expect(adapter.lastObservedRoute.renderId, 'usb-out');
  });

  test('stop and failed start clear Observed and Native Formats', () async {
    final backend = _RecordingBackend();
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
    addTearDown(adapter.stopNative);

    await adapter.startNative(captureId: 'usb-in', renderId: 'usb-out');
    expect(adapter.lastNativeFormats.capture, isNotNull);
    await adapter.stopNative();
    expect(adapter.lastObservedRoute.captureId, isNull);
    expect(adapter.lastNativeFormats.capture, isNull);

    await adapter.startNative(captureId: 'usb-in', renderId: 'usb-out');
    backend.failBind = true;
    final failed = await adapter.startNative(
      captureId: 'usb-in',
      renderId: 'usb-out',
    );
    expect(failed, NativeGraphStart.failed);
    expect(adapter.lastObservedRoute.captureId, isNull);
    expect(adapter.lastNativeFormats.capture, isNull);

    backend.failBind = false;
    final restarted = await adapter.startNative(
      captureId: 'usb-in',
      renderId: 'usb-out',
    );
    expect(restarted, NativeGraphStart.started);
    expect(adapter.lastObservedRoute.captureId, 'usb-in');
    expect(adapter.lastNativeFormats.capture, isNotNull);
  });

  test(
    'packaged Bluetooth identity stays empty when capability lookup fails',
    () async {
      var enumerated = false;
      final source = Win32BluetoothIdentitySource(
        isPackaged: () => true,
        requestCapability: (_) async => null,
        enumerate: () {
          enumerated = true;
          return const [
            BluetoothIdentity(name: 'Tesla Model Y', classOfDevice: 0x420),
          ];
        },
      );
      await source.prepare();
      expect(enumerated, isFalse);
      expect(source.current(), isEmpty);
    },
  );

  test('denied Bluetooth identity leaves WASAPI names', () async {
    final source = Win32BluetoothIdentitySource(
      isPackaged: () => true,
      requestCapability: (_) async => MicrophonePermission.denied,
      enumerate: () => throw StateError('denied Bluetooth must not enumerate'),
    );
    await source.prepare();
    expect(source.current(), isEmpty);
  });

  test(
    'unpackaged Bluetooth identity enumerates without a Store prompt',
    () async {
      var capabilityCalls = 0;
      final source = Win32BluetoothIdentitySource(
        isPackaged: () => false,
        requestCapability: (_) async {
          capabilityCalls++;
          return MicrophonePermission.denied;
        },
        enumerate: () => const [
          BluetoothIdentity(name: 'Tesla Model Y', classOfDevice: 0x420),
        ],
      );
      await source.prepare();
      expect(capabilityCalls, 0);
      expect(source.current().single.name, 'Tesla Model Y');
    },
  );

  test('Bluetooth identity enriches matching Endpoints', () async {
    final backend = _BluetoothBackend();
    final adapter = FlutterAiCommunicationsWindows(
      backend: backend,
      bluetooth: _FixedBluetoothSource(const [
        BluetoothIdentity(name: 'Tesla Model Y', classOfDevice: 0x420),
      ]),
    );
    addTearDown(adapter.stopNative);
    final catalog = await adapter.enumerateEndpoints();
    final tesla = catalog.firstWhere((endpoint) => endpoint.id == 'bt-in');
    expect(tesla.identityHints, ['Tesla Model Y']);
    expect(tesla.capabilities.formFactor, EndpointFormFactor.car);
  });

  test('car Class of Device is a car form factor', () {
    expect(windowsFormFactorFromClassOfDevice(0x420), EndpointFormFactor.car);
  });

  test('Bluetooth prepare failure leaves WASAPI catalog', () async {
    final adapter = FlutterAiCommunicationsWindows(
      backend: _RecordingBackend(),
      bluetooth: _ThrowingBluetoothSource(),
    );
    addTearDown(adapter.stopNative);
    final catalog = await adapter.enumerateEndpoints();
    await Future<void>.delayed(Duration.zero);
    expect(catalog.map((endpoint) => endpoint.id), contains('usb-in'));
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

  test(
    'startNative keeps catalog available without a prior subscriber',
    () async {
      final backend = _RecordingBackend();
      final adapter = FlutterAiCommunicationsWindows(backend: backend);
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

final class _FixedConsent implements WindowsMicrophoneConsent {
  _FixedConsent(this.result);

  final MicrophonePermission result;

  @override
  Future<MicrophonePermission> request() async => result;
}

final class _RecordingConsent implements WindowsMicrophoneConsent {
  var calls = 0;
  MicrophonePermission result = MicrophonePermission.granted;

  @override
  Future<MicrophonePermission> request() async {
    calls++;
    return result;
  }
}

final class _ThrowingBluetoothSource implements BluetoothIdentitySource {
  @override
  List<BluetoothIdentity> current() => const [];

  @override
  Future<void> prepare() async => throw StateError('bluetooth unavailable');
}

final class _FixedBluetoothSource implements BluetoothIdentitySource {
  _FixedBluetoothSource(this._devices);

  final List<BluetoothIdentity> _devices;

  @override
  List<BluetoothIdentity> current() => _devices;

  @override
  Future<void> prepare() async {}
}

final class _BluetoothBackend implements WasapiBackend {
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
  NativeFormatReport get nativeFormats => _inner.nativeFormats;

  @override
  void flush() => _inner.flush();

  @override
  Stream<Uint8List> get capture => _inner.capture;

  @override
  bool startLoopback() => _inner.startLoopback();

  @override
  void stopLoopback() => _inner.stopLoopback();

  @override
  Stream<Uint8List> get loopback => _inner.loopback;

  @override
  void dispose() => _inner.dispose();
}

final class _RecordingBackend implements WasapiBackend {
  PairingSnapshot bound = const PairingSnapshot();
  var failBind = false;
  var probeCalls = 0;

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
  MicrophonePermission probePermission() {
    probeCalls++;
    return MicrophonePermission.granted;
  }

  @override
  NativeGraphStart start({String? captureId, String? renderId}) {
    if (failBind) {
      bound = const PairingSnapshot();
      return NativeGraphStart.failed;
    }
    final capture = _presentId(captureId);
    final render = _presentId(renderId);
    if (capture == null && render == null) {
      bound = const PairingSnapshot(
        captureId: 'built-in-in',
        renderId: 'built-in-out',
      );
    } else {
      bound = PairingSnapshot(captureId: capture, renderId: render);
    }
    return NativeGraphStart.started;
  }

  String? _presentId(String? id) => id == null || id.isEmpty ? null : id;

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
  bool startLoopback() => false;

  @override
  void stopLoopback() {}

  @override
  Stream<Uint8List> get loopback => const Stream.empty();

  @override
  void dispose() {}
}
