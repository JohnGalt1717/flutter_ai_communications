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

  test('probe order tries requested Format before ranked PCM', () {
    expect(
      negotiator.probeOrder(requested: AudioFormat.pcm16le24k).take(3).toList(),
      [
        AudioFormat.pcm16le24k,
        const AudioFormat.pcm16le(sampleRate: 48000),
        const AudioFormat.pcm16le(sampleRate: 16000),
      ],
    );
  });

  test('known capabilities probe exact match only', () {
    expect(
      negotiator.probeOrder(
        requested: AudioFormat.pcm16le24k,
        capabilities: const [
          AudioFormat.pcm16le(sampleRate: 16000),
          AudioFormat.pcm16le24k,
          AudioFormat.pcm16le(sampleRate: 48000),
        ],
      ),
      [AudioFormat.pcm16le24k],
    );
  });

  test('known capabilities without an exact match are ranked', () {
    expect(
      negotiator.probeOrder(
        requested: AudioFormat.pcm16le24k,
        capabilities: const [
          AudioFormat.pcm16le(sampleRate: 44100),
          AudioFormat.pcm16le(sampleRate: 16000),
          AudioFormat.pcm16le(sampleRate: 48000),
        ],
      ),
      [
        const AudioFormat.pcm16le(sampleRate: 48000),
        const AudioFormat.pcm16le(sampleRate: 16000),
        const AudioFormat.pcm16le(sampleRate: 44100),
      ],
    );
  });

  test('withEdges does not fill an unused Session direction', () {
    const report = NativeFormatReport();
    final adopted = report.withEdges(
      capture: AudioFormat.pcm16le24k,
      playback: AudioFormat.pcm16le24k,
      hasCapture: true,
      hasPlayback: false,
    );
    expect(adopted.capture, AudioFormat.pcm16le24k);
    expect(adopted.playback, isNull);
    expect(adopted.playbackPath, ConversionPath.identity);
  });

  test('rejected candidates stay structured', () {
    expect(
      negotiator.failures(
        selected: const AudioFormat.pcm16le(sampleRate: 48000),
        rejected: const [AudioFormat.pcm16le24k],
        rankedOut: const [AudioFormat.pcm16le(sampleRate: 44100)],
      ),
      [
        const FormatCandidateFailure(
          format: AudioFormat.pcm16le24k,
          reason: 'unsupported',
        ),
        const FormatCandidateFailure(
          format: AudioFormat.pcm16le(sampleRate: 44100),
          reason: 'ranked_out',
        ),
      ],
    );
  });
}
