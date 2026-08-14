import 'dart:typed_data';

import 'voice_metrics.dart';

/// Local barge-in: flush playback and keep a preroll of the first word.
final class BargeIn {
  /// Creates a barge-in buffer.
  BargeIn({this.preroll = const Duration(milliseconds: 250)});

  static const _analyzer = VoiceAnalyzer();

  /// How much capture to keep ahead of the barge-in frame.
  final Duration preroll;

  final List<Uint8List> _buffer = <Uint8List>[];
  var _bufferedSamples = 0;
  var playbackActive = false;

  /// Marks that the host is rendering.
  void onPlay() {
    playbackActive = true;
  }

  /// Playback was flushed or paused.
  void onIdle() {
    playbackActive = false;
  }

  /// Stores [frame] in the preroll ring (PCM16 LE mono).
  void remember(Uint8List frame, int sampleRate) {
    _buffer.add(frame);
    _bufferedSamples += frame.length ~/ 2;
    final maxSamples = (sampleRate * preroll.inMilliseconds / 1000).round();
    while (_buffer.length > 1 && _bufferedSamples - _buffer.first.length ~/ 2 > maxSamples) {
      _bufferedSamples -= _buffer.removeAt(0).length ~/ 2;
    }
  }

  /// Whether [frame] looks like user speech.
  bool isVoice(Uint8List frame, int sampleRate) =>
      _analyzer.analyze(frame, sampleRate).isVoice;

  /// Drains the preroll (including frames already remembered).
  List<Uint8List> takePreroll() {
    final out = List<Uint8List>.of(_buffer);
    _buffer.clear();
    _bufferedSamples = 0;
    return out;
  }
}
