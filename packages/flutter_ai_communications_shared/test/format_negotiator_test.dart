import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  const negotiator = FormatNegotiator();

  test('empty capabilities keep the requested Format', () {
    expect(
      negotiator.resolve(requested: AudioFormat.pcm16le24k),
      AudioFormat.pcm16le24k,
    );
  });

  test('exact capability is selected', () {
    expect(
      negotiator.resolve(
        requested: AudioFormat.pcm16le24k,
        capabilities: const [
          AudioFormat.pcm16le(sampleRate: 16000),
          AudioFormat.pcm16le24k,
        ],
      ),
      AudioFormat.pcm16le24k,
    );
  });

  test('missing 24 kHz prefers integer-ratio PCM16', () {
    expect(
      negotiator.resolve(
        requested: AudioFormat.pcm16le24k,
        capabilities: const [
          AudioFormat.pcm16le(sampleRate: 44100),
          AudioFormat.pcm16le(sampleRate: 16000),
          AudioFormat.pcm16le(sampleRate: 48000),
        ],
      ),
      const AudioFormat.pcm16le(sampleRate: 48000),
    );
  });

  test('identity path only when Native equals edge', () {
    expect(
      negotiator.path(AudioFormat.pcm16le24k, AudioFormat.pcm16le24k),
      ConversionPath.identity,
    );
    expect(
      negotiator.path(
        const AudioFormat.pcm16le(sampleRate: 16000),
        AudioFormat.pcm16le24k,
      ),
      ConversionPath.dart,
    );
  });
}
