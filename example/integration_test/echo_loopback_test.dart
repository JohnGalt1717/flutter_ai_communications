import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/echo/fixture_pcm.dart';
import 'package:flutter_ai_communications_example/echo/loopback_platform.dart';
import 'package:flutter_ai_communications_example/echo/loopback_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Real-device echo: play fixture, receive it on capture, pick Endpoint,
/// play again. Analog speaker → microphone is not this path.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live Session echoes fixture byte for byte after select', (
    tester,
  ) async {
    final loopback = LoopbackCommunicationsPlatform.wrapRegistered();
    addTearDown(loopback.dispose);

    final manager = AudioManager();
    addTearDown(() async {
      await manager.session?.stop();
    });

    final result = await manager.start(
      preference: const SessionPreference(
        captureId: LoopbackCommunicationsPlatform.captureId,
        renderId: LoopbackCommunicationsPlatform.renderId,
        soundFloor: 0,
      ),
      bargeInPolicy: BargeInPolicy.remoteVad,
    );
    if (result is! StartReady) {
      markTestSkipped('start failed ($result) — grant the microphone');
      return;
    }
    final session = result.session;
    final capture = session.capture;
    final probe = const LoopbackProbe();
    final firstFixture = FixturePcm.voiceBand24k();

    final first = await probe.echo(
      session: session,
      fixture: firstFixture,
      captureBefore: capture,
    );
    expect(first.identical, isTrue, reason: '${first.bytes} B vs fixture');
    expect(first.clipped, isFalse);
    expect(first.sameCaptureStream, isTrue);

    final endpoints = await manager.endpoints();
    final other = endpoints
        .where(
          (endpoint) =>
              endpoint.isCapture &&
              endpoint.id != LoopbackCommunicationsPlatform.captureId,
        )
        .firstOrNull;
    if (other != null) {
      await session.select(captureId: other.id);
    }

    final secondFixture = FixturePcm.voiceBand24k(phase: 1);
    final second = await probe.echo(
      session: session,
      fixture: secondFixture,
      captureBefore: capture,
    );
    expect(identical(session.capture, capture), isTrue);
    expect(second.identical, isTrue, reason: 'post-select ${second.bytes} B');
    expect(second.clipped, isFalse);
    expect(second.sameCaptureStream, isTrue);
    expect(second.captureId, LoopbackCommunicationsPlatform.captureId);
  });
}
