/// Encoding, sample rate, and channel layout of a Session edge.
enum AudioEncoding {
  /// Linear PCM, 16-bit little-endian.
  pcm16le,

  /// G.711 µ-law.
  pcmu,

  /// G.711 A-law.
  pcma,

  /// Raw Opus packets (Grok: 24 kHz mono).
  opus,
}

/// Format of capture-out or playback-in bytes.
final class AudioFormat {
  /// Creates a Format.
  const AudioFormat({
    required this.encoding,
    required this.sampleRate,
    this.channels = 1,
  });

  /// PCM16 LE mono at [sampleRate].
  const AudioFormat.pcm16le({required int sampleRate, int channels = 1})
    : this(
        encoding: AudioEncoding.pcm16le,
        sampleRate: sampleRate,
        channels: channels,
      );

  /// G.711 µ-law at 8 kHz mono.
  const AudioFormat.pcmu()
    : encoding = AudioEncoding.pcmu,
      sampleRate = 8000,
      channels = 1;

  /// G.711 A-law at 8 kHz mono.
  const AudioFormat.pcma()
    : encoding = AudioEncoding.pcma,
      sampleRate = 8000,
      channels = 1;

  /// Opus 24 kHz mono packets (Grok).
  const AudioFormat.opus()
    : encoding = AudioEncoding.opus,
      sampleRate = 24000,
      channels = 1;

  /// OpenAI required / Grok default: PCM16 LE mono 24 kHz.
  static const AudioFormat pcm16le24k = AudioFormat.pcm16le(sampleRate: 24000);

  /// Encoding of the byte stream.
  final AudioEncoding encoding;

  /// Sample rate in Hz.
  final int sampleRate;

  /// Channel count. Communications audio is mono.
  final int channels;

  /// PCM sample rates supported by Grok (OpenAI PCM is 24 kHz only).
  static const Set<int> pcmSampleRates = {
    8000,
    16000,
    22050,
    24000,
    32000,
    44100,
    48000,
  };

  /// Whether this Format is in the OpenAI + Grok set.
  bool get isSupported {
    if (channels != 1) {
      return false;
    }
    return switch (encoding) {
      AudioEncoding.pcm16le => pcmSampleRates.contains(sampleRate),
      AudioEncoding.pcmu || AudioEncoding.pcma => sampleRate == 8000,
      AudioEncoding.opus => sampleRate == 24000,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AudioFormat &&
      other.encoding == encoding &&
      other.sampleRate == sampleRate &&
      other.channels == channels;

  @override
  int get hashCode => Object.hash(encoding, sampleRate, channels);

  @override
  String toString() =>
      'AudioFormat(${encoding.name}, ${sampleRate}Hz, $channels ch)';
}
