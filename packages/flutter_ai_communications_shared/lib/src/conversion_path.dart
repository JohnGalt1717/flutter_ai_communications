import 'audio_format.dart';

/// How a Session edge Format relates to the Native Format.
enum ConversionPath {
  /// Native Format equals the Session edge Format. No converter.
  identity,

  /// One shared Dart converter sits between Native Format and the edge.
  dart,

  /// A verified platform/OS converter sits between Native Format and the edge.
  platform,
}

/// Why a Native Format candidate was rejected during Format negotiation.
final class FormatCandidateFailure {
  /// Creates a structured candidate failure.
  const FormatCandidateFailure({required this.format, required this.reason});

  /// Candidate that did not initialize or was ranked out.
  final AudioFormat format;

  /// Machine-readable reason. Never user-facing copy.
  final String reason;
}
