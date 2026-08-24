import 'dart:typed_data';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  const sampleRate = 24000;
  final t0 = DateTime.utc(2026, 1, 1);

  PlaybackTimeline timelineAt(DateTime now) =>
      PlaybackTimeline(sampleRate: sampleRate, clock: () => now);

  test('two chunks abut without overlap or gap', () {
    var now = t0;
    final timeline = PlaybackTimeline(sampleRate: sampleRate, clock: () => now);
    final first = timeline.schedule(
      _pcm(seconds: 0.05, sampleRate: sampleRate),
    )!;
    final second = timeline.schedule(
      _pcm(seconds: 0.05, sampleRate: sampleRate),
    )!;

    expect(first.start, Duration.zero);
    expect(first.end, second.start);
    expect(second.end, const Duration(milliseconds: 100));
    expect(second.start < first.end, isFalse);
    expect(timeline.queued, 2);
    expect(timeline.rendered, 0);
    expect(timeline.remaining, const Duration(milliseconds: 100));
  });

  test('flush drops remaining and does not leave stale schedule', () {
    var now = t0;
    final timeline = PlaybackTimeline(sampleRate: sampleRate, clock: () => now);
    timeline.schedule(_pcm(seconds: 0.05, sampleRate: sampleRate));
    timeline.schedule(_pcm(seconds: 0.05, sampleRate: sampleRate));
    now = t0.add(const Duration(milliseconds: 20));
    timeline.observe();
    timeline.flush();

    expect(timeline.remaining, Duration.zero);
    expect(timeline.queued, 0);
    expect(timeline.flushed, 1);
    expect(timeline.rendered, 0);

    now = t0.add(const Duration(milliseconds: 20));
    final next = timeline.schedule(
      _pcm(seconds: 0.05, sampleRate: sampleRate),
    )!;
    expect(next.start, const Duration(milliseconds: 20));
    expect(next.end, const Duration(milliseconds: 70));
  });

  test('pause and resume preserve remaining seconds', () {
    var now = t0;
    final timeline = PlaybackTimeline(sampleRate: sampleRate, clock: () => now);
    timeline.schedule(_pcm(seconds: 0.10, sampleRate: sampleRate));
    now = t0.add(const Duration(milliseconds: 20));
    timeline.pause();
    expect(timeline.remaining, const Duration(milliseconds: 80));

    now = t0.add(const Duration(milliseconds: 500));
    timeline.observe();
    expect(timeline.remaining, const Duration(milliseconds: 80));
    expect(timeline.queued, 1);

    timeline.resume();
    final next = timeline.schedule(
      _pcm(seconds: 0.05, sampleRate: sampleRate),
    )!;
    expect(next.start, const Duration(milliseconds: 100));
    expect(timeline.remaining, const Duration(milliseconds: 130));
  });

  test('observe marks finished chunks rendered from the queue', () {
    var now = t0;
    final timeline = PlaybackTimeline(sampleRate: sampleRate, clock: () => now);
    timeline.schedule(_pcm(seconds: 0.05, sampleRate: sampleRate));
    expect(timeline.queued, 1);
    expect(timeline.rendered, 0);

    now = t0.add(const Duration(milliseconds: 50));
    timeline.observe();
    expect(timeline.queued, 0);
    expect(timeline.rendered, 1);
    expect(timeline.remaining, Duration.zero);
  });

  test('empty bytes are not scheduled', () {
    final timeline = timelineAt(t0);
    final slot = timeline.schedule(Uint8List(0));
    expect(slot, isNull);
    expect(timeline.accepted, 0);
    expect(timeline.queued, 0);
  });
}

Uint8List _pcm({required double seconds, required int sampleRate}) {
  return Uint8List((sampleRate * seconds).round() * 2);
}
