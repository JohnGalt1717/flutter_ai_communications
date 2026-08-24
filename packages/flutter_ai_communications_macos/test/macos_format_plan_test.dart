import 'package:flutter_ai_communications_macos/src/macos_format_plan.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact 24 kHz mono capability is identity', () {
    final plan = planMacNativeFormat(
      channels: 1,
      availableRates: const [24000, 48000],
    );
    expect(plan.native, AudioFormat.pcm16le24k);
    expect(plan.needsConvert, isFalse);
  });

  test('24 kHz stereo downmixes at the same rate', () {
    final plan = planMacNativeFormat(
      channels: 2,
      availableRates: const [24000, 48000],
    );
    expect(plan.native.sampleRate, 24000);
    expect(plan.native.channels, 2);
    expect(plan.needsConvert, isTrue);
  });

  test('48 kHz stereo USB takes best quality and converts', () {
    final plan = planMacNativeFormat(
      channels: 2,
      availableRates: const [48000],
    );
    expect(
      plan.native,
      const AudioFormat.pcm16le(sampleRate: 48000, channels: 2),
    );
    expect(plan.edge, AudioFormat.pcm16le24k);
    expect(plan.needsConvert, isTrue);
  });

  test('48 kHz beats 16 kHz even though both integer-ratio 24 kHz', () {
    final plan = planMacNativeFormat(
      channels: 1,
      availableRates: const [16000, 48000],
    );
    expect(plan.native.sampleRate, 48000);
  });

  test(
    'undiscovered capabilities assume 48 kHz at the given channel count',
    () {
      final plan = planMacNativeFormat(channels: 2);
      expect(plan.native.sampleRate, 48000);
      expect(plan.native.channels, 2);
      expect(plan.needsConvert, isTrue);
    },
  );

  test('discrete rates expand a continuous HAL range', () {
    expect(macosDiscreteRates([(8000.0, 48000.0)]), [
      8000,
      16000,
      22050,
      24000,
      32000,
      44100,
      48000,
    ]);
    expect(macosDiscreteRates([(48000.0, 48000.0)]), [48000]);
  });
}
