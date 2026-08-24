import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_web/src/web_route_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AirPods are bluetooth even though the browser lists them as audioinput', () {
    expect(
      webRouteClass(name: "James's AirPods Pro", isCapture: true),
      RouteClass.bluetooth,
    );
    expect(
      webRouteClass(name: "James's AirPods Pro", isCapture: false),
      RouteClass.bluetooth,
    );
  });

  test('Chrome Default- prefix does not hide AirPods or BRIO', () {
    expect(
      webRouteClass(
        name: 'Default - James’s AirPods Pro',
        isCapture: true,
      ),
      RouteClass.bluetooth,
    );
    expect(
      webRouteClass(name: 'Default - Logitech BRIO (046d:085e)', isCapture: true),
      RouteClass.wired,
    );
  });

  test('USB and headset labels stay wired', () {
    expect(
      webRouteClass(name: 'Realtek USB2.0 Audio', isCapture: true),
      RouteClass.wired,
    );
    expect(
      webRouteClass(name: 'USB Headset', isCapture: false),
      RouteClass.wired,
    );
  });

  test('built-in Mac speakers and mics are speakerphone', () {
    expect(
      webRouteClass(name: 'MacBook Pro Microphone', isCapture: true),
      RouteClass.speakerphone,
    );
    expect(
      webRouteClass(name: 'MacBook Pro Speakers', isCapture: false),
      RouteClass.speakerphone,
    );
  });
}
