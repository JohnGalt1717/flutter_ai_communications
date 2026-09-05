import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_windows/flutter_ai_communications_windows.dart';
import 'package:flutter_ai_communications_windows/src/screen_channel.dart';
import 'package:flutter_ai_communications_windows/src/wasapi_backend.dart';
import 'package:flutter_ai_communications_windows/src/windows_screen_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_ai_communications/methods');

  test('Windows catalog includes display, window, and All-displays', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enumerateScreenSources') {
            return [
              {
                'id': 'display-0',
                'name': '\\\\.\\DISPLAY1',
                'kind': 'display',
                'width': 1920,
                'height': 1080,
                'canPreview': true,
              },
              {
                'id': 'all-displays',
                'name': 'All displays',
                'kind': 'allDisplays',
                'width': 1920,
                'height': 1080,
                'canPreview': true,
              },
              {
                'id': 'window-1',
                'name': 'untitled.txt',
                'kind': 'window',
                'applicationName': 'Notepad',
                'width': 800,
                'height': 600,
                'canPreview': true,
              },
            ];
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsWindows(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    final catalog = await adapter.enumerateScreenSources();
    expect(catalog.map((source) => source.kind), [
      ScreenSourceKind.display,
      ScreenSourceKind.allDisplays,
      ScreenSourceKind.window,
    ]);
    expect(catalog.last.name, 'Notepad — untitled.txt');
    expect(catalog.last.applicationName, 'Notepad');
  });

  test('Windows startScreenShare maps a texture handle', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          if (call.method == 'startScreenShareNative') {
            return {
              'status': 'started',
              'textureId': 9,
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
    final adapter = FlutterAiCommunicationsWindows(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(
      await adapter.startScreenShareNative(sourceId: 'display-0'),
      NativeGraphStart.started,
    );
    expect(adapter.lastScreenSurface?.handle, 9);
  });

  test('Include sound uses WASAPI FFI loopback, not the screen channel',
      () async {
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
    final backend = _LoopbackWasapi();
    final adapter = FlutterAiCommunicationsWindows(
      backend: backend,
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    expect(backend.starts, 1);
    expect(screenAudioCalls, 0);
    await adapter.stopScreenShareNative();
    expect(backend.stops, 1);
  });

  test('unpackaged Win32 skips Store screen consent', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final packaged = _RecordingScreenConsent()..result = ScreenPermission.denied;
    final adapter = FlutterAiCommunicationsWindows(
      screen: MethodChannelScreenBackend(methods: channel),
      screenConsent: GatedWindowsScreenConsent(
        isPackaged: () => false,
        packaged: packaged,
      ),
    );
    expect(await adapter.requestScreenPermission(), ScreenPermission.granted);
    expect(packaged.calls, 0);
  });

  test('packaged Store host requests screen consent', () async {
    var nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            nativeCalls++;
            return 'granted';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final packaged = _RecordingScreenConsent()..result = ScreenPermission.denied;
    final adapter = FlutterAiCommunicationsWindows(
      screen: MethodChannelScreenBackend(methods: channel),
      screenConsent: GatedWindowsScreenConsent(
        isPackaged: () => true,
        packaged: packaged,
      ),
    );
    expect(await adapter.requestScreenPermission(), ScreenPermission.denied);
    expect(packaged.calls, 1);
    expect(nativeCalls, 0);
  });

  test('granted Store screen consent still asks the native graph', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsWindows(
      screen: MethodChannelScreenBackend(methods: channel),
      screenConsent: GatedWindowsScreenConsent(
        isPackaged: () => true,
        packaged: _RecordingScreenConsent(),
      ),
    );
    expect(await adapter.requestScreenPermission(), ScreenPermission.granted);
  });

  test('AppCapabilityAccessStatus maps to ScreenPermission', () {
    expect(screenPermissionFromAppCapabilityStatus(4), ScreenPermission.granted);
    expect(screenPermissionFromAppCapabilityStatus(2), ScreenPermission.denied);
    expect(screenPermissionFromAppCapabilityStatus(1), ScreenPermission.denied);
    expect(
      screenPermissionFromAppCapabilityStatus(0),
      ScreenPermission.restricted,
    );
    expect(screenPermissionFromAppCapabilityStatus(3), isNull);
  });

  test('Include sound off stops WASAPI loopback', () async {
    final backend = _LoopbackWasapi();
    final adapter = FlutterAiCommunicationsWindows(backend: backend);
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    expect(await adapter.setIncludeSystemAudioNative(false), isFalse);
    expect(backend.starts, 1);
    expect(backend.stops, 1);
  });
}

final class _RecordingScreenConsent implements WindowsScreenConsent {
  var calls = 0;
  ScreenPermission result = ScreenPermission.granted;

  @override
  Future<ScreenPermission> request() async {
    calls++;
    return result;
  }
}

final class _LoopbackWasapi implements WasapiBackend {
  var starts = 0;
  var stops = 0;

  @override
  List<Endpoint> enumerate() => const [];

  @override
  MicrophonePermission probePermission() => MicrophonePermission.granted;

  @override
  NativeGraphStart start({String? captureId, String? renderId}) =>
      NativeGraphStart.unavailable;

  @override
  void stop() {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void play(Uint8List bytes) {}

  @override
  void select({String? captureId, String? renderId}) {}

  @override
  PairingSnapshot get observed => const PairingSnapshot();

  @override
  NativeFormatReport get nativeFormats => const NativeFormatReport();

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
