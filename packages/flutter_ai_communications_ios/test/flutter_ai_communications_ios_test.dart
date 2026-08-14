import 'package:flutter_ai_communications_ios/flutter_ai_communications_ios.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS adapter registers and names itself ios', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsIos.registerWith();
    expect(FlutterAiCommunicationsPlatform.instance, isA<FlutterAiCommunicationsIos>());
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'ios');
    FlutterAiCommunicationsPlatform.debugReset();
  });
}
