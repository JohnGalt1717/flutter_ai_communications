import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_linux/flutter_ai_communications_linux.dart';
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
}