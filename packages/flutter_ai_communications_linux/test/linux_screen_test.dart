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
      ScreenSourceKind.systemPicker,
    });
  });
}