import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_windows/flutter_ai_communications_windows.dart';
import 'package:flutter_ai_communications_windows/src/route_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows adapter registers and names itself windows', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsWindows.registerWith();
    expect(
      FlutterAiCommunicationsPlatform.instance,
      isA<FlutterAiCommunicationsWindows>(),
    );
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'windows');
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('Windows Isolation is unavailable', () {
    final adapter = FlutterAiCommunicationsWindows();
    expect(adapter.lastIsolation.state, IsolationState.unavailable);
  });

  test('built-in speakers pair as speakerphone', () {
    expect(
      windowsRouteClass(name: 'Speakers (Realtek)', enumerator: 'HDAUDIO'),
      RouteClass.speakerphone,
    );
    expect(
      windowsPairId(
        routeClass: RouteClass.speakerphone,
        id: 'id',
        name: 'Speakers',
      ),
      windowsBuiltInPairId,
    );
  });

  test('Bluetooth and USB headsets keep their RouteClass', () {
    expect(
      windowsRouteClass(name: 'AirPods', enumerator: 'BTHENUM'),
      RouteClass.bluetooth,
    );
    expect(
      windowsRouteClass(name: 'USB Headset', enumerator: 'USB'),
      RouteClass.wired,
    );
  });
}
