import 'package:flutter_ai_communications_macos/flutter_ai_communications_macos.dart';
import 'package:flutter_ai_communications_macos/src/route_class.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
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

  test('macOS Isolation is unavailable', () {
    final adapter = FlutterAiCommunicationsMacos();
    expect(adapter.lastIsolation.state, IsolationState.unavailable);
  });

  test('built-in speakers pair as speakerphone', () {
    expect(
      macosRouteClass(name: 'MacBook Pro Microphone', transport: 'bltn'),
      RouteClass.speakerphone,
    );
    expect(
      macosPairId(
        routeClass: RouteClass.speakerphone,
        id: 'id',
        name: 'Speakers',
      ),
      macosBuiltInPairId,
    );
  });

  test('AirPods capture and render share one Pair identity', () {
    expect(
      macosPairId(
        routeClass: RouteClass.bluetooth,
        id: 'HFP-UID',
        name: 'AirPods Microphone',
        uid: 'HFP-UID',
      ),
      macosPairId(
        routeClass: RouteClass.bluetooth,
        id: 'A2DP-UID',
        name: 'AirPods',
        uid: 'A2DP-UID',
      ),
    );
  });

  test('Bluetooth and USB headsets keep their RouteClass', () {
    expect(
      macosRouteClass(name: 'AirPods', transport: 'blue'),
      RouteClass.bluetooth,
    );
    expect(
      macosRouteClass(name: 'USB Headset', transport: 'usb'),
      RouteClass.wired,
    );
  });
}
