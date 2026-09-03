import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_macos/flutter_ai_communications_macos.dart';
import 'package:flutter_ai_communications_macos/src/screen_channel.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_ai_communications/methods');

  test('macOS catalog includes display, window, and All-displays', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enumerateScreenSources') {
            return [
              {
                'id': 'display-1',
                'name': 'Built-in Retina Display',
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
                'id': 'window-42',
                'name': 'Finder',
                'kind': 'window',
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
    final adapter = FlutterAiCommunicationsMacos(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    final catalog = await adapter.enumerateScreenSources();
    expect(catalog.map((source) => source.kind), [
      ScreenSourceKind.display,
      ScreenSourceKind.allDisplays,
      ScreenSourceKind.window,
    ]);
  });

  test('macOS startScreenShare maps a texture handle', () async {
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
              'kind': 'texture',
            };
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsMacos(
      screen: MethodChannelScreenBackend(methods: channel),
    );
    expect(
      await adapter.startScreenShareNative(sourceId: 'display-1'),
      NativeGraphStart.started,
    );
    expect(adapter.lastScreenSurface?.handle, 11);
  });
}
