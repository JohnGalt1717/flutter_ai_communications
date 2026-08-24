import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  test('voice during playback is barge-in and preroll is kept', () {
    final barge = BargeIn(preroll: const Duration(milliseconds: 250));
    const rate = 24000;
    final rumble = _tone(
      sampleRate: rate,
      hz: 80,
      seconds: 0.05,
      amplitude: 800,
    );
    final word = _tone(
      sampleRate: rate,
      hz: 700,
      seconds: 0.05,
      amplitude: 14000,
    );

    barge.onPlay();
    barge.remember(rumble, rate);
    expect(barge.isVoice(word, rate), isTrue);
    final preroll = barge.takePreroll();
    expect(preroll, isNotEmpty);
    expect(preroll.first, rumble);
  });

  test('idle barge-in is not playback-active', () {
    final barge = BargeIn();
    expect(barge.playbackActive, isFalse);
    barge.onPlay();
    expect(barge.playbackActive, isTrue);
    barge.onIdle();
    expect(barge.playbackActive, isFalse);
  });
}

Uint8List _tone({
  required int sampleRate,
  required double hz,
  required double seconds,
  required int amplitude,
}) {
  final count = (sampleRate * seconds).round();
  final out = Uint8List(count * 2);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < count; i++) {
    final sample = (math.sin(2 * math.pi * hz * i / sampleRate) * amplitude)
        .round()
        .clamp(-32767, 32767);
    data.setInt16(i * 2, sample, Endian.little);
  }
  return out;
}
