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
}
