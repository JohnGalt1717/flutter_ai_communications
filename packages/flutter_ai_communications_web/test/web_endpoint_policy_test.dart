import 'package:flutter_ai_communications_web/src/web_endpoint_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = WebEndpointPolicy();

  test('capture plan applies exact deviceId', () {
    final plan = policy.capturePlan('mic-1');
    expect(plan.deviceId, 'mic-1');
    expect(plan.constrainDevice, isTrue);
  });

  test('blank capture id uses the browser default', () {
    expect(policy.capturePlan(null).constrainDevice, isFalse);
    expect(policy.capturePlan('').deviceId, isNull);
  });

  test('render plan uses sinkId when supported', () {
    final plan = policy.renderPlan('speaker-out', sinkSupported: true);
    expect(plan.sinkId, 'speaker-out');
    expect(plan.unsupported, isNull);
  });

  test('unsupported sink is a typed path and status', () {
    final plan = policy.renderPlan('speaker-out', sinkSupported: false);
    expect(plan.sinkId, isNull);
    expect(plan.unsupported?.path, 'AudioContext.sinkId');
    expect(plan.unsupported?.statusCode, 'unsupported');
  });
}
