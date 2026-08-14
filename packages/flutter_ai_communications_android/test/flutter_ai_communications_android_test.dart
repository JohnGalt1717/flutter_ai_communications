import 'package:flutter_ai_communications_android/flutter_ai_communications_android.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android adapter registers and names itself android', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsAndroid.registerWith();
    expect(
      FlutterAiCommunicationsPlatform.instance,
      isA<FlutterAiCommunicationsAndroid>(),
    );
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'android');
    FlutterAiCommunicationsPlatform.debugReset();
  });
}
