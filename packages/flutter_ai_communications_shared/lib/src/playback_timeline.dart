import 'dart:typed_data';

/// One scheduled playback chunk on a monotonic timeline.
final class PlaybackSlot {
  /// Creates a scheduled slot.
  const PlaybackSlot({
    required this.start,
    required this.end,
    required this.bytes,
  });

  /// Start offset from the timeline origin.
  final Duration start;

  /// End offset from the timeline origin.
  final Duration end;

  /// PCM bytes for this chunk.
  final Uint8List bytes;

  /// Scheduled duration.
  Duration get duration => end - start;
}

/// Monotonic playback queue for streamed PCM chunks.
///
/// [play] return is not render. [observe] retires finished slots from the
/// queue. Pause freezes the playhead; flush drops remaining; reset leaves
/// the queue in place.
final class PlaybackTimeline {
  /// Creates a timeline for [sampleRate] PCM16 LE mono.
  PlaybackTimeline({required this.sampleRate, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Working sample rate.
  final int sampleRate;

  final DateTime Function() _clock;
  final List<PlaybackSlot> _slots = <PlaybackSlot>[];

  DateTime? _origin;
  Duration _playhead = Duration.zero;
  Duration _cursor = Duration.zero;
  var _paused = false;

  /// Chunks accepted by [schedule].
  var accepted = 0;

  /// Chunks still waiting to finish.
  var queued = 0;

  /// Chunks retired after their end time.
  var rendered = 0;

  /// How many times [flush] ran.
  var flushed = 0;

  /// Whether the playhead is frozen.
  bool get isPaused => _paused;

  /// Time left from the playhead to the last scheduled end.
  Duration get remaining {
    if (_slots.isEmpty) {
      return Duration.zero;
    }
    final end = _slots.last.end;
    return end > _playhead ? end - _playhead : Duration.zero;
  }

  /// Schedules [bytes] so they abut the previous chunk.
  PlaybackSlot? schedule(Uint8List bytes) {
    observe();
    final samples = bytes.length ~/ 2;
    if (samples == 0) {
      return null;
    }
    accepted++;
    queued++;
    _origin ??= _clock();
    final duration = Duration(microseconds: (samples * 1000000) ~/ sampleRate);
    final start = _cursor > _playhead ? _cursor : _playhead;
    final end = start + duration;
    _cursor = end;
    final slot = PlaybackSlot(start: start, end: end, bytes: bytes);
    _slots.add(slot);
    return slot;
  }

  /// Drops remaining audio. The next [schedule] starts at the playhead.
  void flush() {
    observe();
    _slots.clear();
    queued = 0;
    flushed++;
    _cursor = _playhead;
  }

  /// Freezes the playhead so pause time does not consume the queue.
  void pause() {
    observe();
    _paused = true;
  }

  /// Continues from the frozen playhead.
  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    final origin = _origin;
    if (origin != null) {
      _origin = _clock().subtract(_playhead);
    }
  }

  /// Retires slots whose end is at or behind the playhead.
  void observe() {
    final origin = _origin;
    if (origin == null) {
      return;
    }
    if (!_paused) {
      final elapsed = _clock().difference(origin);
      if (elapsed > _playhead) {
        _playhead = elapsed;
      }
    }
    _slots.removeWhere((slot) {
      if (slot.end > _playhead) {
        return false;
      }
      if (queued > 0) {
        queued--;
      }
      rendered++;
      return true;
    });
  }
}
