import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(FlutterAiCommunicationsPlatform.debugReset);
  tearDown(FlutterAiCommunicationsPlatform.debugReset);

  test('app package reads the registered platform name', () {
    FlutterAiCommunicationsPlatform.instance = _FakePlatform();
    expect(FlutterAiCommunications.platformName, 'fake');
  });

  test('app package re-exports shared types', () {
    expect(sharedPackageName, 'flutter_ai_communications_shared');
  });
}

final class _FakePlatform extends FlutterAiCommunicationsPlatform {
  @override
  String get platformName => 'fake';
}
