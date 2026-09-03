import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_ios/flutter_ai_communications_ios.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_ai_communications/methods');

  test('iOS catalog is one system-picker source', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enumerateScreenSources') {
            return [
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
    final adapter = FlutterAiCommunicationsIos();
    final catalog = await adapter.enumerateScreenSources();
    expect(catalog, hasLength(1));
    expect(catalog.single.id, 'system-picker');
    expect(catalog.single.kind, ScreenSourceKind.systemPicker);
    expect(catalog.single.canPreview, isFalse);
  });

  test('iOS startScreenShare maps a texture handle', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          if (call.method == 'startScreenShareNative') {
            return {
              'status': 'started',
              'textureId': 7,
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
    final adapter = FlutterAiCommunicationsIos();
    expect(
      await adapter.startScreenShareNative(sourceId: 'system-picker'),
      NativeGraphStart.started,
    );
    expect(adapter.lastScreenSurface?.handle, 7);
  });

  test('iOS OS decline maps to unavailable denied', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          if (call.method == 'startScreenShareNative') {
            return {'status': 'unavailable', 'reason': 'denied'};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsIos();
    expect(
      await adapter.startScreenShareNative(sourceId: 'system-picker'),
      NativeGraphStart.unavailable,
    );
    expect(adapter.lastScreenUnavailableReason, 'denied');
    expect(adapter.lastScreenSurface, isNull);
  });
}
