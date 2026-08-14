import 'dart:io';

import 'package:flutter_ai_communications_example/echo/fixture_pcm.dart';

void main() {
  final pcm = FixturePcm.voiceBand24k();
  final wav = FixturePcm.toWav(pcm, sampleRate: 24000);
  File('assets/voice_band_24k.wav').writeAsBytesSync(wav);
  stdout.writeln('wrote ${wav.length} bytes');
}
