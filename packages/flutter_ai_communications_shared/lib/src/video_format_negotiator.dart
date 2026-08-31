import 'video_format.dart';

/// Picks a Native Video Format closest to a request.
///
/// Next higher resolution if any exists, otherwise the next lower. Frame rate
/// closest to the request, preferring at least the requested fps when tied.
final class VideoFormatNegotiator {
  /// Creates a negotiator.
  const VideoFormatNegotiator();

  /// Returns the closest [modes] entry to [requested], or null if [modes] is empty.
  VideoFormat? nearest(VideoFormat requested, List<VideoFormat> modes) {
    if (modes.isEmpty) {
      return null;
    }
    final higher = modes.where((mode) => mode.pixelCount >= requested.pixelCount);
    final band = higher.isNotEmpty
        ? _minPixels(higher)
        : _maxPixels(modes);
    final sameRes = modes.where((mode) => mode.pixelCount == band.pixelCount);
    return _closestFps(requested.frameRate, sameRes);
  }

  VideoFormat _minPixels(Iterable<VideoFormat> modes) {
    var best = modes.first;
    for (final mode in modes) {
      if (mode.pixelCount < best.pixelCount) {
        best = mode;
      }
    }
    return best;
  }

  VideoFormat _maxPixels(Iterable<VideoFormat> modes) {
    var best = modes.first;
    for (final mode in modes) {
      if (mode.pixelCount > best.pixelCount) {
        best = mode;
      }
    }
    return best;
  }

  VideoFormat _closestFps(int requested, Iterable<VideoFormat> modes) {
    VideoFormat? best;
    var bestDistance = 1 << 30;
    for (final mode in modes) {
      final distance = (mode.frameRate - requested).abs();
      if (best == null ||
          distance < bestDistance ||
          (distance == bestDistance &&
              mode.frameRate >= requested &&
              best.frameRate < requested)) {
        best = mode;
        bestDistance = distance;
      }
    }
    return best!;
  }
}
