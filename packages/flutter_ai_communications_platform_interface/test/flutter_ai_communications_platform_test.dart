import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(FlutterAiCommunicationsPlatform.debugReset);
  tearDown(FlutterAiCommunicationsPlatform.debugReset);

  test('instance throws until a platform adapter registers', () {
    expect(
      () => FlutterAiCommunicationsPlatform.instance,
      throwsA(isA<StateError>()),
    );
  });

  test('a registered adapter is the instance', () {
    FlutterAiCommunicationsPlatform.instance = _FakePlatform();
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'fake');
  });
}

final class _FakePlatform extends FlutterAiCommunicationsPlatform {
  @override
  String get platformName => 'fake';
}
