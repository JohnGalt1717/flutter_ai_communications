import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/meeting/flutter_webrtc_loopback.dart';
import 'package:flutter_ai_communications_example/meeting/video_surface_view.dart';
import 'package:flutter_ai_communications_webrtc/flutter_ai_communications_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'inbound falls back to the Send track Video surface without mapSendTrack',
    () async {
      final loopback = FlutterWebRtcLoopback();
      addTearDown(loopback.dispose);
      var notified = 0;
      loopback.inboundChanged = () => notified++;
      await loopback.applySendTrack(
        const WebrtcSendTrack(
          id: 'video-1',
          generation: 1,
          muteVideo: false,
          processor: NoneVideoProcessor(),
          surface: VideoSurface(handle: 7),
        ),
      );
      expect(notified, greaterThan(0));
      expect(loopback.inboundView(), isA<VideoSurfaceView>());
    },
  );
}
