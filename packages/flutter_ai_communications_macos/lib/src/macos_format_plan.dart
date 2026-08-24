import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Native Format chosen for a Core Audio Endpoint, plus the Session edge.
///
/// When the Endpoint cannot do PCM16 mono 24 kHz, [native] is the best
/// quality PCM16 the device actually has. The adapter transcodes once
/// to [edge] before bytes leave the platform.
final class MacNativeFormatPlan {
  /// Creates a plan.
  const MacNativeFormatPlan({
    required this.native,
    this.edge = AudioFormat.pcm16le24k,
  });

  /// HAL / AudioQueue Format. May be stereo or a rate other than 24 kHz.
  final AudioFormat native;

  /// Session-edge Format. Always PCM16 LE mono 24 kHz for v1.
  final AudioFormat edge;

  /// Whether the adapter must convert Native → edge (or the reverse).
  bool get needsConvert =>
      native.sampleRate != edge.sampleRate || native.channels != edge.channels;
}

/// Discrete rates the HAL advertised, including values inside a continuous
/// range that match known PCM rates.
List<int> macosDiscreteRates(Iterable<(double, double)> ranges) {
  const known = [8000, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000];
  final out = <int>{};
  for (final (min, max) in ranges) {
    if ((max - min).abs() < 0.5) {
      final rate = min.round();
      if (rate > 0) {
        out.add(rate);
      }
      continue;
    }
    for (final rate in known) {
      if (rate + 0.5 >= min && rate - 0.5 <= max) {
        out.add(rate);
      }
    }
  }
  return out.toList()..sort();
}

/// Picks the Native Format for an Endpoint.
///
/// Exact Session-edge Format wins when it is a real capability. Otherwise
/// take the highest-quality advertised PCM and leave conversion to the
/// adapter. Empty [availableRates] means discovery failed — assume a
/// high-quality communications device (48 kHz) rather than 24 kHz, which
/// USB class devices often reject with silence.
MacNativeFormatPlan planMacNativeFormat({
  required int channels,
  List<int> availableRates = const [],
  AudioFormat requested = AudioFormat.pcm16le24k,
}) {
  final ch = channels < 1 ? 1 : channels;
  final rates = [
    for (final rate in availableRates)
      if (rate > 0) rate,
  ];

  bool has(int rate) => rates.isEmpty || rates.contains(rate);

  if (has(requested.sampleRate) &&
      ch == requested.channels &&
      rates.isNotEmpty) {
    return MacNativeFormatPlan(native: requested);
  }
  if (rates.isNotEmpty && rates.contains(requested.sampleRate)) {
    return MacNativeFormatPlan(
      native: AudioFormat.pcm16le(
        sampleRate: requested.sampleRate,
        channels: ch,
      ),
    );
  }

  const ranked = [48000, 44100, 32000, 24000, 22050, 16000, 8000];
  int? best;
  var bestScore = -1;
  final candidates = rates.isEmpty ? ranked.take(1) : rates;
  for (final rate in candidates) {
    final rank = ranked.indexOf(rate);
    var score = rank >= 0 ? (ranked.length - rank) * 1000 : rate;
    if (rate % requested.sampleRate == 0 || requested.sampleRate % rate == 0) {
      score += 1;
    }
    if (score > bestScore) {
      bestScore = score;
      best = rate;
    }
  }
  return MacNativeFormatPlan(
    native: AudioFormat.pcm16le(sampleRate: best ?? 48000, channels: ch),
  );
}
