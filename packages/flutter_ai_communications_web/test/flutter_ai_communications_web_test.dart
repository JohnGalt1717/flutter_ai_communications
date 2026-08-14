import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web documented limits: no Isolation, no handset Endpoint in the model', () {
    const isolation = IsolationEvent(IsolationState.unavailable);
    expect(isolation.state, IsolationState.unavailable);

    const speaker = Endpoint(
      id: 'default-out',
      name: 'Default',
      routeClass: RouteClass.speakerphone,
      isCapture: false,
    );
    expect(speaker.routeClass, isNot(RouteClass.handset));
  });
}
