import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_web/src/web_endpoint_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = WebEndpointPolicy();

  test('capture plan applies exact deviceId', () {
    final plan = policy.capturePlan('mic-1');
    expect(plan.deviceId, 'mic-1');
    expect(plan.constrainDevice, isTrue);
  });

  test('capture-only does not want playback', () {
    expect(policy.wantsCapture('mic-1', null), isTrue);
    expect(policy.wantsPlayback('mic-1', null), isFalse);
  });

  test('playback-only does not want capture', () {
    expect(policy.wantsCapture(null, 'speaker-out'), isFalse);
    expect(policy.wantsPlayback(null, 'speaker-out'), isTrue);
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

  test('native Format is PCM16 at the AudioContext sample rate', () {
    expect(
      policy.nativeFormat(sampleRate: 48000),
      const AudioFormat.pcm16le(sampleRate: 48000),
    );
    expect(policy.nativeFormat(sampleRate: 44100.4).sampleRate, 44100);
  });

  test('unsupported sink is a typed path and status', () {
    final plan = policy.renderPlan('speaker-out', sinkSupported: false);
    expect(plan.sinkId, isNull);
    expect(plan.unsupported?.path, 'AudioContext.sinkId');
    expect(plan.unsupported?.statusCode, 'unsupported');
  });

  test('Observed render is the applied sink, never the requested id', () {
    expect(policy.observedRenderId(appliedSinkId: 'usb-out'), 'usb-out');
    expect(policy.observedRenderId(appliedSinkId: null), isNull);
    expect(policy.observedRenderId(appliedSinkId: ''), isNull);
  });

  test('unsupported sink leaves Observed render null', () {
    expect(
      policy.observedRenderId(
        appliedSinkId: 'usb-out',
        unsupported: const WebSinkUnsupported(
          path: 'AudioContext.sinkId',
          statusCode: 'unsupported',
        ),
      ),
      isNull,
    );
  });

  test('first start opens a context for the Desired sink', () {
    expect(
      policy.sinkBind(
        contextOpen: false,
        appliedSinkId: null,
        desiredSinkId: 'airpods-out',
        stopping: false,
      ),
      WebSinkBind.open,
    );
  });

  test('same applied sink keeps the live context', () {
    expect(
      policy.sinkBind(
        contextOpen: true,
        appliedSinkId: 'airpods-out',
        desiredSinkId: 'airpods-out',
        stopping: false,
      ),
      WebSinkBind.keep,
    );
  });

  test('render pick replaces the context so the new sink is applied', () {
    expect(
      policy.sinkBind(
        contextOpen: true,
        appliedSinkId: 'airpods-out',
        desiredSinkId: 'usb-out',
        stopping: false,
      ),
      WebSinkBind.replace,
    );
  });

  test('stop closes an open context', () {
    expect(
      policy.sinkBind(
        contextOpen: true,
        appliedSinkId: 'airpods-out',
        desiredSinkId: 'airpods-out',
        stopping: true,
      ),
      WebSinkBind.close,
    );
  });

  test('a new Session after stop opens a fresh context', () {
    expect(
      policy.sinkBind(
        contextOpen: false,
        appliedSinkId: null,
        desiredSinkId: 'airpods-out',
        stopping: false,
      ),
      WebSinkBind.open,
    );
  });
}
