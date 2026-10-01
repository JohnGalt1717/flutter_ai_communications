import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  test('HFP and A2DP UIDs share the hardware token', () {
    expect(
      applePairId(
        routeClass: RouteClass.bluetooth,
        uid: 'AA:BB:CC:DD:EE:FF-tsco',
        name: 'AirPods Microphone',
      ),
      'AA:BB:CC:DD:EE:FF',
    );
    expect(
      applePairId(
        routeClass: RouteClass.bluetooth,
        uid: 'AA:BB:CC:DD:EE:FF-tacl',
        name: 'AirPods',
      ),
      'AA:BB:CC:DD:EE:FF',
    );
  });

  test('different hardware tokens stay different with the same name', () {
    expect(
      applePairId(
        routeClass: RouteClass.bluetooth,
        uid: '11:11:11:11:11:11-tsco',
        name: 'AirPods Pro',
      ),
      isNot(
        applePairId(
          routeClass: RouteClass.bluetooth,
          uid: '22:22:22:22:22:22-tacl',
          name: 'AirPods Pro',
        ),
      ),
    );
  });

  test('uid without a profile suffix is returned unchanged', () {
    expect(
      applePairId(
        routeClass: RouteClass.wired,
        uid: 'AppleUSBAudioEngine:Generic:USB Audio:1141200:1',
        name: 'USB Audio',
      ),
      'AppleUSBAudioEngine:Generic:USB Audio:1141200:1',
    );
  });

  test('handset and speakerphone stay distinguishable', () {
    expect(
      applePairId(
        routeClass: RouteClass.handset,
        uid: 'Built-In Microphone',
        name: 'iPhone Microphone',
      ),
      'handset',
    );
    expect(
      applePairId(
        routeClass: RouteClass.speakerphone,
        uid: 'Speaker',
        name: 'Speaker',
      ),
      'speakerphone',
    );
  });
}
