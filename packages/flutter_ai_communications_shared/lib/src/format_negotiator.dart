import 'audio_format.dart';
import 'conversion_path.dart';

/// Selects a verified Native Format from Endpoint capabilities.
///
/// Prefers an exact Session edge Format. Otherwise ranks PCM16 by
/// communications processing, integer-ratio conversion, and rate distance.
/// Failure-first probing is not this module — callers only probe when
/// [capabilities] is empty.
final class FormatNegotiator {
  /// Creates a negotiator.
  const FormatNegotiator();

  static const List<int> _pcmRank = [
    24000,
    48000,
    16000,
    32000,
    44100,
    22050,
    8000,
  ];

  /// Picks the Native Format for [requested] from [capabilities].
  ///
  /// Empty [capabilities] means discovery was unavailable; the requested
  /// Format is returned so the platform can probe.
  AudioFormat resolve({
    required AudioFormat requested,
    List<AudioFormat> capabilities = const [],
  }) {
    if (capabilities.isEmpty) {
      return requested;
    }
    for (final candidate in capabilities) {
      if (candidate == requested) {
        return candidate;
      }
    }
    AudioFormat? best;
    var bestScore = -1;
    for (final candidate in capabilities) {
      if (!candidate.isSupported || candidate.encoding == AudioEncoding.opus) {
        continue;
      }
      final score = _score(requested, candidate);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best ?? requested;
  }

  /// Conversion path between Native Format and the Session edge.
  ConversionPath path(AudioFormat native, AudioFormat edge) {
    return native == edge ? ConversionPath.identity : ConversionPath.dart;
  }

  int _score(AudioFormat requested, AudioFormat candidate) {
    if (candidate.encoding != AudioEncoding.pcm16le) {
      if (candidate.encoding == requested.encoding) {
        return 10;
      }
      return 1;
    }
    var score = 50;
    final rank = _pcmRank.indexOf(candidate.sampleRate);
    if (rank >= 0) {
      score += 20 - rank;
    }
    if (_integerRatio(requested.sampleRate, candidate.sampleRate)) {
      score += 15;
    }
    final distance = (requested.sampleRate - candidate.sampleRate).abs();
    score += (20 - (distance / 2400).round()).clamp(0, 20);
    return score;
  }

  bool _integerRatio(int a, int b) {
    if (a == 0 || b == 0) {
      return false;
    }
    return a % b == 0 || b % a == 0;
  }
}

/// Native Formats accepted by the last start, reset, or Endpoint apply.
final class NativeFormatReport {
  /// Creates a report.
  const NativeFormatReport({
    this.capture,
    this.playback,
    this.capturePath = ConversionPath.identity,
    this.playbackPath = ConversionPath.identity,
    this.failures = const [],
  });

  /// Negotiated Native capture Format.
  final AudioFormat? capture;

  /// Negotiated Native playback Format.
  final AudioFormat? playback;

  /// How Native capture relates to the Session capture edge.
  final ConversionPath capturePath;

  /// How Native playback relates to the Session playback edge.
  final ConversionPath playbackPath;

  /// Candidates that did not initialize or were ranked out.
  final List<FormatCandidateFailure> failures;

  /// Fills missing Native Formats from the Session edge Formats.
  NativeFormatReport withEdges({
    required AudioFormat capture,
    required AudioFormat playback,
  }) {
    const negotiator = FormatNegotiator();
    final nativeCapture = this.capture ?? capture;
    final nativePlayback = this.playback ?? playback;
    return NativeFormatReport(
      capture: nativeCapture,
      playback: nativePlayback,
      capturePath: negotiator.path(nativeCapture, capture),
      playbackPath: negotiator.path(nativePlayback, playback),
      failures: failures,
    );
  }
}
