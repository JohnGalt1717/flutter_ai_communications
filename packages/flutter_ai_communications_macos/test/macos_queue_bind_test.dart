import 'package:flutter_ai_communications_macos/src/macos_queue_bind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bind success reports the bound UID', () {
    const bind = MacQueueBind(setStatus: 0, boundUid: 'usb-in');
    expect(bind.applied('usb-in'), isTrue);
    expect(observedQueueUid(boundUid: bind.boundUid), 'usb-in');
  });

  test('bind failure does not report the requested UID', () {
    const bind = MacQueueBind(setStatus: -50, boundUid: null);
    expect(bind.applied('usb-in'), isFalse);
    expect(observedQueueUid(boundUid: bind.boundUid), isNull);
  });

  test('OS that ignores set reports the actually bound UID', () {
    const bind = MacQueueBind(setStatus: 0, boundUid: 'built-in-in');
    expect(bind.applied('usb-in'), isFalse);
    expect(observedQueueUid(boundUid: bind.boundUid), 'built-in-in');
  });

  test(
    'failed set still reports whatever GetProperty bound, not the request',
    () {
      const bind = MacQueueBind(setStatus: -50, boundUid: 'built-in-in');
      expect(bind.applied('usb-in'), isFalse);
      expect(observedQueueUid(boundUid: bind.boundUid), 'built-in-in');
    },
  );
}
