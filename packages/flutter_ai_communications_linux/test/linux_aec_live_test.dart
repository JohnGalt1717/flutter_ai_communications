import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_ai_communications_linux/src/pulse_backend.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const _lifeCam =
    'alsa_input.usb-Microsoft_Microsoft___LifeCam_Studio_TM_-02.mono-fallback';
const _plantronics =
    'alsa_output.usb-Plantronics_Plantronics_Savi_8200_Office_Series_B90959610971448EABE358CE9BAD7D6E-01.mono-fallback';

void main() {
  test(
    'analog AEC: Plantronics playback is quieter on LifeCam with Speex',
    () async {
      final off = await _toneRms(aec: false);
      final on = await _toneRms(aec: true);
      // ignore: avoid_print
      print('LifeCam RMS AEC-off=$off AEC-on=$on ratio=${on / (off + 1)}');
      expect(off, greaterThan(1e6), reason: 'LifeCam should hear the headset');
      expect(on, lessThan(off * 0.6));
    },
    skip: Platform.environment['FAC_AEC_LIVE'] == '1'
        ? false
        : 'set FAC_AEC_LIVE=1 for analog prove',
  );
}

Future<double> _toneRms({required bool aec}) async {
  final backend = PulseAudioBackend();
  addTearDown(backend.dispose);
  expect(
    backend.start(
      captureId: _lifeCam,
      renderId: _plantronics,
      noiseCancelling: aec,
    ),
    NativeGraphStart.started,
  );
  final frames = <Uint8List>[];
  final sub = backend.capture.listen(frames.add);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  for (var i = 0; i < 180; i++) {
    backend.play(_sineFrame(i));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await sub.cancel();
  backend.stop();
  expect(frames, isNotEmpty);
  final tail = frames.length > 40 ? frames.sublist(frames.length - 40) : frames;
  var energy = 0.0;
  var samples = 0;
  for (final frame in tail) {
    final s = frame.buffer.asInt16List();
    for (var i = 0; i < s.length; i++) {
      final v = s[i].toDouble();
      energy += v * v;
      samples++;
    }
  }
  return energy / samples;
}

Uint8List _sineFrame(int frame) {
  final bytes = Uint8List(480);
  final samples = bytes.buffer.asInt16List();
  for (var i = 0; i < 240; i++) {
    final n = frame * 240 + i;
    samples[i] = (sin(2 * pi * 1000 * n / 24000) * 12000).round();
  }
  return bytes;
}
