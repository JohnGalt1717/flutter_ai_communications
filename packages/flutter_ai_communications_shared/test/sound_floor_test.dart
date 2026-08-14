import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  test('lounge rumble is dropped after the adaptive floor rises', () {
    final floor = SoundFloor();
    const rate = 24000;
    final lounge = _tone(sampleRate: rate, hz: 80, seconds: 0.12, amplitude: 4000);
    final voice = _tone(sampleRate: rate, hz: 700, seconds: 0.12, amplitude: 14000);

    for (var i = 0; i < 8; i++) {
      floor.apply(lounge, sampleRate: rate);
    }
    expect(floor.noiseRms, greaterThan(0.02));

    final gatedLounge = floor.apply(lounge, sampleRate: rate);
    expect(gatedLounge, Uint8List(lounge.length));

    final passedVoice = floor.apply(voice, sampleRate: rate);
    expect(passedVoice, voice);
  });

  test('fixed floor is honored; null returns to adaptive', () {
    final floor = SoundFloor(fixed: 0.9);
    const rate = 24000;
    final voice = _tone(sampleRate: rate, hz: 700, seconds: 0.08, amplitude: 8000);
    expect(floor.apply(voice, sampleRate: rate), Uint8List(voice.length));

    floor.setFloor(null);
    expect(floor.fixed, isNull);
    final quiet = _tone(sampleRate: rate, hz: 80, seconds: 0.08, amplitude: 400);
    floor.apply(quiet, sampleRate: rate);
    expect(floor.noiseRms, greaterThan(0));
  });

  test('fixed zero is a pass-through', () {
    final floor = SoundFloor(fixed: 0);
    const rate = 24000;
    final lounge = _tone(
      sampleRate: rate,
      hz: 80,
      seconds: 0.08,
      amplitude: 4000,
    );
    expect(floor.apply(lounge, sampleRate: rate), lounge);
  });

  test('car route raises the adaptive floor', () {
    final floor = SoundFloor();
    expect(
      floor.threshold(routeClass: RouteClass.car),
      greaterThan(floor.threshold()),
    );
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
