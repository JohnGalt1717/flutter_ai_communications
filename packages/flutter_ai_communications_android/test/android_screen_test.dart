import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_android/flutter_ai_communications_android.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_ai_communications/methods');

  test('Android catalog is one system-picker source', () async {
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
    final adapter = FlutterAiCommunicationsAndroid();
    final catalog = await adapter.enumerateScreenSources();
    expect(catalog.single.kind, ScreenSourceKind.systemPicker);
  });

  test('Include sound true does not fail share', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          if (call.method == 'startScreenShareNative') {
            return {
              'status': 'started',
              'textureId': 4,
              'width': 1080,
              'height': 1920,
              'frameRate': 5,
              'systemAudio': true,
            };
          }
          if (call.method == 'setIncludeSystemAudioNative') {
            return call.arguments['enabled'] == true;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsAndroid();
    expect(
      await adapter.startScreenShareNative(
        sourceId: 'system-picker',
        includeSystemAudio: true,
      ),
      NativeGraphStart.started,
    );
    expect(adapter.lastScreenSurface?.handle, 4);
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    expect(await adapter.setIncludeSystemAudioNative(false), isFalse);
  });

  test('Include sound false does not fail share', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          if (call.method == 'startScreenShareNative') {
            return {
              'status': 'started',
              'textureId': 5,
              'width': 1080,
              'height': 1920,
              'frameRate': 5,
              'systemAudio': false,
            };
          }
          if (call.method == 'setIncludeSystemAudioNative') {
            return false;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsAndroid();
    expect(
      await adapter.startScreenShareNative(sourceId: 'system-picker'),
      NativeGraphStart.started,
    );
    expect(await adapter.setIncludeSystemAudioNative(true), isFalse);
  });

  test('Mute does not disable Include sound', () async {
    var includeEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestScreenPermission') {
            return 'granted';
          }
          if (call.method == 'startScreenShareNative') {
            includeEnabled = true;
            return {
              'status': 'started',
              'textureId': 6,
              'width': 1080,
              'height': 1920,
              'frameRate': 5,
              'systemAudio': true,
            };
          }
          if (call.method == 'setIncludeSystemAudioNative') {
            includeEnabled = call.arguments['enabled'] == true;
            return includeEnabled;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final adapter = FlutterAiCommunicationsAndroid();
    expect(
      await adapter.startScreenShareNative(
        sourceId: 'system-picker',
        includeSystemAudio: true,
      ),
      NativeGraphStart.started,
    );
    expect(includeEnabled, isTrue);
    expect(await adapter.setIncludeSystemAudioNative(true), isTrue);
    expect(includeEnabled, isTrue);
  });
}
