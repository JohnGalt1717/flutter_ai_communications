import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

import 'echo_transport.dart';
import 'fixture_pcm.dart';
import 'loopback_platform.dart';
import 'pcm_quality.dart';

/// One identity leg: stream, optionally after an Endpoint pick.
final class EchoProof {
  /// Creates a proof snapshot.
  const EchoProof({
    required this.identical,
    required this.clipped,
    required this.bytes,
    required this.peak,
    required this.rms,
    required this.captureId,
    required this.renderId,
    required this.sameCaptureStream,
  });

  /// Capture bytes matched the fixture exactly.
  final bool identical;

  /// Any full-scale sample.
  final bool clipped;

  /// Bytes received on this leg.
  final int bytes;

  /// Peak PCM16 sample.
  final int peak;

  /// RMS 0–1.
  final double rms;

  /// Capture Endpoint used.
  final String? captureId;

  /// Render Endpoint used.
  final String? renderId;

  /// Session.capture object did not change.
  final bool sameCaptureStream;
}

/// Plays fixture PCM and records what the Transport receives.
final class LoopbackProbe {
  /// Creates a probe.
  const LoopbackProbe();

  static const _frameBytes = 480;
  static const _asset = 'assets/voice_band_24k.wav';

  /// Loads the committed fixture WAV.
  Future<Uint8List> loadFixture() async {
    final data = await rootBundle.load(_asset);
    return FixturePcm.readWav(data.buffer.asUint8List());
  }

  /// Digital identity: inject fixture as native capture, require byte match.
  Future<EchoProof> digital({
    required Session session,
    required void Function(Uint8List bytes) inject,
    required Uint8List fixture,
    Stream<Uint8List>? captureBefore,
  }) async {
    final before = captureBefore ?? session.capture;
    final echo = EchoTransport(session);
    await echo.attach();
    echo.beginLeg();
    inject(fixture);
    await Future<void>.delayed(Duration.zero);
    final received = echo.received;
    await echo.dispose();
    return _proof(
      session: session,
      fixture: fixture,
      received: received,
      sameCaptureStream: identical(before, session.capture),
    );
  }

  /// Host loopback: [Session.play] after the native adapter accepts the
  /// fixture, then capture must be those same bytes.
  Future<EchoProof> echo({
    required Session session,
    required Uint8List fixture,
    Stream<Uint8List>? captureBefore,
  }) async {
    final before = captureBefore ?? session.capture;
    final previousFloor = session.soundFloor;
    session.setSoundFloor(0);
    final transport = EchoTransport(session, replay: false);
    await transport.attach();
    if (session.selectedCaptureId !=
        LoopbackCommunicationsPlatform.captureId) {
      await session.select(
        captureId: LoopbackCommunicationsPlatform.captureId,
        renderId: LoopbackCommunicationsPlatform.renderId,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }
    transport.beginLeg();
    try {
      await _playFrames(session, fixture);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return _proof(
        session: session,
        fixture: fixture,
        received: transport.received,
        sameCaptureStream: identical(before, session.capture),
      );
    } finally {
      await transport.dispose();
      session.setSoundFloor(previousFloor);
    }
  }

  /// Live device: play fixture, collect capture, check quality (not bit-identity).
  ///
  /// Speaker → microphone cannot be byte-identical. This leg proves frames
  /// still arrive, the capture stream object survived, and nothing clipped.
  Future<EchoProof> live({
    required Session session,
    Duration playFor = const Duration(milliseconds: 800),
    Stream<Uint8List>? captureBefore,
  }) async {
    final before = captureBefore ?? session.capture;
    final previousFloor = session.soundFloor;
    session.setSoundFloor(0);
    Uint8List fixture;
    try {
      fixture = await loadFixture();
    } on Object {
      fixture = FixturePcm.voiceBand24k(seconds: playFor.inMilliseconds / 1000);
    }
    final echo = EchoTransport(session, replay: false);
    await echo.attach();
    echo.beginLeg();
    try {
      await _playFrames(session, fixture);
      final deadline = DateTime.now().add(playFor + const Duration(seconds: 1));
      while (echo.received.length <= 480 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return _proof(
        session: session,
        fixture: fixture,
        received: echo.received,
        sameCaptureStream: identical(before, session.capture),
      );
    } finally {
      await echo.dispose();
      session.setSoundFloor(previousFloor);
    }
  }

  EchoProof _proof({
    required Session session,
    required Uint8List fixture,
    required Uint8List received,
    required bool sameCaptureStream,
  }) {
    return EchoProof(
      identical: _bytesEqual(received, fixture),
      clipped: PcmQuality.clipped(received),
      bytes: received.length,
      peak: PcmQuality.peak(received),
      rms: PcmQuality.rms(received),
      captureId: session.selectedCaptureId,
      renderId: session.selectedRenderId,
      sameCaptureStream: sameCaptureStream,
    );
  }

  Future<void> _playFrames(Session session, Uint8List pcm) async {
    for (var offset = 0; offset < pcm.length; offset += _frameBytes) {
      final end = offset + _frameBytes > pcm.length
          ? pcm.length
          : offset + _frameBytes;
      await session.play(Uint8List.sublistView(pcm, offset, end));
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
