import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('flutter_ai_communications/methods');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelCommunicationsPlatform platform;
  final calls = <MethodCall>[];

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    calls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return switch (call.method) {
        'enumerateEndpoints' => [
          {
            'id': 'handset-in',
            'name': 'Handset',
            'routeClass': 'handset',
            'isCapture': true,
            'pairId': 'handset',
          },
          {
            'id': 'speaker-out',
            'name': 'Speakerphone',
            'routeClass': 'speakerphone',
            'isCapture': false,
            'pairId': 'speakerphone',
          },
        ],
        'requestMicrophonePermission' => 'denied',
        'startNative' => 'started',
        _ => null,
      };
    });
    platform = MethodChannelCommunicationsPlatform(platformName: 'ios');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(methods, null);
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('catalog includes handset and speakerphone from native maps', () async {
    final catalog = await platform.enumerateEndpoints();
    expect(catalog.any((e) => e.routeClass == RouteClass.handset), isTrue);
    expect(catalog.any((e) => e.routeClass == RouteClass.speakerphone), isTrue);
  });

  test('denied permission is a value, not an exception', () async {
    expect(
      await platform.requestMicrophonePermission(),
      MicrophonePermission.denied,
    );
  });

  test('startNative and selectEndpoints keep the same capture stream', () async {
    final capture = platform.nativeCapture;
    expect(await platform.startNative(captureId: 'handset-in'), NativeGraphStart.started);
    await platform.selectEndpoints(captureId: 'handset-in', renderId: 'speaker-out');
    expect(identical(platform.nativeCapture, capture), isTrue);
    expect(calls.any((c) => c.method == 'startNative'), isTrue);
    expect(calls.any((c) => c.method == 'selectEndpoints'), isTrue);
  });

  test('openIsolationSettings is forwarded', () async {
    await platform.openIsolationSettings();
    expect(calls.any((c) => c.method == 'openIsolationSettings'), isTrue);
  });
}
