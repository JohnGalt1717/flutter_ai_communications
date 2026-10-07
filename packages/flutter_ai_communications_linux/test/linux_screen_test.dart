import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_linux/flutter_ai_communications_linux.dart';
import 'package:flutter_ai_communications_linux/src/audio_backend.dart';
import 'package:flutter_ai_communications_linux/src/screen_channel.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_ai_communications/methods');

  test('Linux catalog maps display, All-displays, and window kinds', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enumerateScreenSources') {
            return [
              {
                'id': 'display-0',
                'name': 'Display 1',
                'kind': 'display',
                'width': 1920,
                'height': 1080,
                'canPreview': false,
              },
              {
                'id': 'all-displays',
                'name': 'All displays',
                'kind': 'allDisplays',
                'width': 1920,
                'height': 1080,
                'canPreview': false,
              },
              {
                'id': 'window-1',
                'name': 'GitHub',
                'kind': 'window',
                'applicationName': 'firefox',
                'width': 800,
                'height': 600,
                'canPreview': true,
              },
              {
                'id': 'system-picker',
                'name': 'System picker',
                'kind': 'systemPicker',
                'canPreview': false,
              },
            ];
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsLinux(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    final catalog = await adapter.enumerateScreenSources();
    expect(catalog.map((source) => source.kind).toSet(), {
      ScreenSourceKind.display,
      ScreenSourceKind.allDisplays,
      ScreenSourceKind.window,
      ScreenSourceKind.systemPicker,
    });
    expect(catalog[2].name, 'firefox — GitHub');
    expect(catalog[2].applicationName, 'firefox');
  });

  test('Linux beginScreenPick maps preview textures', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'beginScreenPickNative') {
            return {
              'previews': {'display-0': 4, 'window-1': 5},
            };
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsLinux(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(await adapter.beginScreenPickNative(), NativeGraphStart.started);
    expect(adapter.screenPreviewNative('display-0')?.handle, 4);
  });

  test('Linux empty beginScreenPick is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'beginScreenPickNative') {
            return {'previews': <String, int>{}};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsLinux(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(await adapter.beginScreenPickNative(), NativeGraphStart.unavailable);
  });

  test('Linux startScreenShare maps a texture handle', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          if (call.method == 'startScreenShareNative') {
            return {
              'status': 'started',
              'textureId': 11,
              'width': 1920,
              'height': 1080,
              'frameRate': 5,
            };
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsLinux(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(
      await adapter.startScreenShareNative(sourceId: 'display-0'),
      NativeGraphStart.started,
    );
    expect(adapter.lastScreenSurface?.handle, 11);
  });

  test('Linux startScreenShare maps PipeWire miss as unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'startScreenShareNative') {
            return {'status': 'unavailable', 'reason': 'pipewire'};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsLinux(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(
      await adapter.startScreenShareNative(sourceId: 'system-picker'),
      NativeGraphStart.unavailable,
    );
    expect(adapter.lastScreenSurface, isNull);
    expect(adapter.lastScreenUnavailableReason, 'pipewire');
  });

  test('Include sound uses Pulse loopback, not the screen channel', () async {
    var screenAudioCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setIncludeSystemAudioNative') {
            screenAudioCalls++;
            return true;
          }
          if (call.method == 'stopScreenShareNative') {
            return null;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final backend = _LoopbackPulse();
    final adapter = FlutterAiCommunicationsLinux(
      backend: backend,
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    expect(backend.starts, 1);
    expect(screenAudioCalls, 0);
    await adapter.stopScreenShareNative();
    expect(backend.stops, 1);
  });

  test('Include sound off stops Pulse loopback', () async {
    final backend = _LoopbackPulse();
    final adapter = FlutterAiCommunicationsLinux(backend: backend);
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    expect(await adapter.setIncludeSystemAudioNative(false), isFalse);
    expect(backend.starts, 1);
    expect(backend.stops, 1);
  });

  test('Replacing screen send stops loopback before native start', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'startScreenShareNative') {
            return {
              'status': 'started',
              'textureId': 7,
              'width': 1280,
              'height': 720,
            };
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final backend = _LoopbackPulse();
    final adapter = FlutterAiCommunicationsLinux(
      backend: backend,
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    expect(backend.starts, 1);
    expect(backend.stops, 0);
    expect(
      await adapter.startScreenShareNative(sourceId: 'display-0'),
      NativeGraphStart.started,
    );
    expect(backend.stops, 1);
  });

  test('selectEndpoints rebinds include-sound loopback', () async {
    final backend = _LoopbackPulse();
    final adapter = FlutterAiCommunicationsLinux(backend: backend);
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    await adapter.selectEndpoints(renderId: 'sink-2');
    expect(backend.lastRenderId, 'sink-2');
    expect(backend.starts, 2);
    expect(backend.stops, 0);
  });
}

final class _LoopbackPulse with DeviceWatchSupport implements AudioBackend {
  var starts = 0;
  var stops = 0;
  String? lastRenderId;

  @override
  List<Endpoint> enumerate() => const [];

  @override
  MicrophonePermission probePermission() => MicrophonePermission.granted;

  @override
  NativeGraphStart start({
    String? captureId,
    String? renderId,
    bool noiseCancelling = true,
  }) => NativeGraphStart.unavailable;

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
    lastRenderId = renderId ?? lastRenderId;
  }

  @override
  PairingSnapshot get observed => const PairingSnapshot();

  @override
  void flush() {}

  @override
  Stream<Uint8List> get capture => const Stream.empty();

  @override
  bool startLoopback() {
    starts++;
    return true;
  }

  @override
  void stopLoopback() => stops++;

  @override
  Stream<Uint8List> get loopback => const Stream.empty();

  @override
  void dispose() {}
}
