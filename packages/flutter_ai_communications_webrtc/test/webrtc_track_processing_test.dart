import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_webrtc/flutter_ai_communications_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(
      webrtcTrackProcessingChannel,
      (call) async => handler(call),
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(webrtcTrackProcessingChannel, null);
  });

  test('sends the track id and the processor encoding', () async {
    MethodCall? seen;
    answer((call) {
      seen = call;
      return 'ready';
    });

    final result = await processWebrtcVideoTrack(
      'track-1',
      const BlurVideoProcessor(intensity: 100),
    );

    expect(result, WebrtcTrackProcessing.applied);
    expect(seen?.method, 'process');
    expect(seen?.arguments, {
      'trackId': 'track-1',
      'processor': {'kind': 'blur', 'intensity': 100},
    });
  });

  test('a replace asset reaches native as bytes', () async {
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      return key == 'assets/office.png'
          ? ByteData.sublistView(Uint8List.fromList([1, 2, 3]))
          : null;
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    Object? sent;
    answer((call) {
      sent = (call.arguments as Map)['processor'];
      return 'ready';
    });

    final result = await processWebrtcVideoTrack(
      't',
      const ReplaceVideoProcessor(asset: 'assets/office.png'),
    );

    expect(result, WebrtcTrackProcessing.applied);
    expect(sent, {
      'kind': 'replace',
      'bytes': Uint8List.fromList([1, 2, 3]),
      'asset': 'assets/office.png',
    });
  });

  test('a missing asset or invalid blur fails closed before native', () async {
    messenger.setMockMessageHandler('flutter/assets', (_) async => null);
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    var calls = 0;
    answer((_) {
      calls++;
      return 'ready';
    });

    expect(
      await processWebrtcVideoTrack(
        't',
        const ReplaceVideoProcessor(asset: 'assets/missing.png'),
      ),
      WebrtcTrackProcessing.unavailable,
    );
    expect(
      await processWebrtcVideoTrack(
        't',
        const BlurVideoProcessor(intensity: 101),
      ),
      WebrtcTrackProcessing.unavailable,
    );
    expect(calls, 0);
  });

  test('native unavailable or invalid fails closed', () async {
    answer((_) => 'unavailable');
    expect(
      await processWebrtcVideoTrack('t', const BlurVideoProcessor()),
      WebrtcTrackProcessing.unavailable,
    );
    answer((_) => 'invalid');
    expect(
      await processWebrtcVideoTrack('t', const BlurVideoProcessor()),
      WebrtcTrackProcessing.unavailable,
    );
  });

  test('an unknown track id is noTrack', () async {
    answer((_) => 'noTrack');
    expect(
      await processWebrtcVideoTrack('gone', const BlurVideoProcessor()),
      WebrtcTrackProcessing.noTrack,
    );
  });

  test('a platform error fails closed', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    expect(
      await processWebrtcVideoTrack('t', const BlurVideoProcessor()),
      WebrtcTrackProcessing.unavailable,
    );
  });

  test('no native bridge: blur is unavailable, none needs nothing', () async {
    expect(
      await processWebrtcVideoTrack('t', const BlurVideoProcessor()),
      WebrtcTrackProcessing.unavailable,
    );
    expect(
      await processWebrtcVideoTrack('t', const NoneVideoProcessor()),
      WebrtcTrackProcessing.applied,
    );
  });

  test('native unavailable reaches webrtcTrackProcessingUnavailable', () async {
    final ids = <String>[];
    final sub = webrtcTrackProcessingUnavailable.listen(ids.add);
    Future<void> native(Object? arguments) => messenger.handlePlatformMessage(
      webrtcTrackProcessingChannel.name,
      webrtcTrackProcessingChannel.codec.encodeMethodCall(
        MethodCall('unavailable', arguments),
      ),
      (_) {},
    );

    await native({'trackId': 'track-1'});
    await native({'trackId': 7});
    await native(null);
    await sub.cancel();

    expect(ids, ['track-1']);
  });
}
