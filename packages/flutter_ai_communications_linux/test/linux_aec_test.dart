import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_ai_communications_linux/src/aec_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SpeexAec.tryStart is null when the library cannot load', () {
    if (SpeexAec.available) {
      expect(SpeexAec.tryStart(), isNotNull);
    } else {
      expect(SpeexAec.tryStart(), isNull);
    }
  });

  test('SpeexAec attenuates delayed playback mixed into capture', () {
    final aec = SpeexAec.tryStart();
    expect(aec, isNotNull);
    addTearDown(aec!.dispose);
    const delayFrames = 5;
    final played = <Uint8List>[];
    var inEnergy = 0.0;
    var outEnergy = 0.0;
    for (var i = 0; i < 80; i++) {
      final play = _sineFrame(i);
      aec.playback(play);
      played.add(play);
      final rec = Uint8List(SpeexAec.frameBytes);
      if (i >= delayFrames) {
        _mix(rec, played[i - delayFrames], 0.5);
      }
      final out = aec.process(rec);
      if (i > 40) {
        inEnergy += _energy(rec);
        outEnergy += _energy(out);
      }
    }
    expect(outEnergy, lessThan(inEnergy * 0.4));
  }, skip: SpeexAec.available ? false : 'libspeexdsp.so.1 missing');
}

Uint8List _sineFrame(int frame) {
  final bytes = Uint8List(SpeexAec.frameBytes);
  final samples = bytes.buffer.asInt16List();
  for (var i = 0; i < SpeexAec.frameSamples; i++) {
    final n = frame * SpeexAec.frameSamples + i;
    samples[i] = (sin(2 * pi * 1000 * n / SpeexAec.sampleRate) * 8000).round();
  }
  return bytes;
}

void _mix(Uint8List dest, Uint8List src, double gain) {
  final d = dest.buffer.asInt16List();
  final s = src.buffer.asInt16List();
  for (var i = 0; i < SpeexAec.frameSamples; i++) {
    d[i] = (s[i] * gain).round();
  }
}

double _energy(Uint8List pcm) {
  final s = pcm.buffer.asInt16List();
  var sum = 0.0;
  for (var i = 0; i < s.length; i++) {
    final v = s[i].toDouble();
    sum += v * v;
  }
  return sum;
}
