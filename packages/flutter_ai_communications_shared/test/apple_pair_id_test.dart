import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  test('AirPods capture and render UIDs share one Pair identity', () {
    expect(
      applePairId(
        routeClass: RouteClass.bluetooth,
        uid: 'AA-HFP-IN',
        name: 'AirPods',
      ),
      applePairId(
        routeClass: RouteClass.bluetooth,
        uid: 'AA-A2DP-OUT',
        name: 'AirPods',
      ),
    );
    expect(
      applePairId(
        routeClass: RouteClass.bluetooth,
        uid: 'AA-HFP-IN',
        name: 'AirPods Microphone',
      ),
      'airpods',
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
