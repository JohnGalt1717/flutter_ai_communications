import 'package:flutter_ai_communications_macos/flutter_ai_communications_macos.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS adapter registers and names itself macos', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsMacos.registerWith();
    expect(
      FlutterAiCommunicationsPlatform.instance,
      isA<FlutterAiCommunicationsMacos>(),
    );
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'macos');
    FlutterAiCommunicationsPlatform.debugReset();
  });
}
