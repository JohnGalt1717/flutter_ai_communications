import 'package:flutter_ai_communications_linux/flutter_ai_communications_linux.dart';
import 'package:flutter_ai_communications_linux/src/route_class.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux adapter registers and names itself linux', () {
    FlutterAiCommunicationsPlatform.debugReset();
    FlutterAiCommunicationsLinux.registerWith();
    expect(
      FlutterAiCommunicationsPlatform.instance,
      isA<FlutterAiCommunicationsLinux>(),
    );
    expect(FlutterAiCommunicationsPlatform.instance.platformName, 'linux');
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('Linux Isolation is unavailable', () {
    final adapter = FlutterAiCommunicationsLinux();
    expect(adapter.lastIsolation.state, IsolationState.unavailable);
  });

  test('built-in analog devices pair as speakerphone', () {
    expect(
      linuxRouteClass(name: 'Built-in Audio Analog Stereo', bus: 'pci'),
      RouteClass.speakerphone,
    );
    expect(
      linuxPairId(
        routeClass: RouteClass.speakerphone,
        id: 'alsa_output.pci',
        name: 'Built-in Audio',
      ),
      linuxBuiltInPairId,
    );
  });

  test('Bluetooth and USB headsets keep their RouteClass', () {
    expect(
      linuxRouteClass(name: 'WH-1000XM5', bus: 'bluetooth'),
      RouteClass.bluetooth,
    );
    expect(
      linuxRouteClass(name: 'USB Headset', bus: 'usb', formFactor: 'headset'),
      RouteClass.wired,
    );
  });
}
