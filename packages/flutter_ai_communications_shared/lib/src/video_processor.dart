/// Library-owned send-path transform. v1 implements only [NoneVideoProcessor].
sealed class VideoProcessor {
  /// Creates a processor.
  const VideoProcessor();
}

/// Pass-through. The only production Video processor in v1.
final class NoneVideoProcessor extends VideoProcessor {
  /// Creates a none processor.
  const NoneVideoProcessor();

  @override
  bool operator ==(Object other) => other is NoneVideoProcessor;

  @override
  int get hashCode => 0;
}

/// Blur with intensity 0–100. Not implemented in v1.
final class BlurVideoProcessor extends VideoProcessor {
  /// Creates a blur processor. [intensity] is 0–100 inclusive.
  const BlurVideoProcessor({this.intensity = 50});

  /// Blur amount. Host UIs map None/Some/Lots to 0/50/100.
  final int intensity;

  /// Whether [intensity] is in range.
  bool get isValid => intensity >= 0 && intensity <= 100;

  @override
  bool operator ==(Object other) =>
      other is BlurVideoProcessor && other.intensity == intensity;

  @override
  int get hashCode => intensity;
}

/// Replace the background with a still. Not implemented in v1.
final class ReplaceVideoProcessor extends VideoProcessor {
  /// Creates a replace processor from still [bytes] or an [asset] path.
  const ReplaceVideoProcessor({this.bytes, this.asset});

  /// Still image bytes.
  final List<int>? bytes;

  /// Asset path for a still image.
  final String? asset;

  /// Whether a still was supplied.
  bool get isValid =>
      (bytes != null && bytes!.isNotEmpty) ||
      (asset != null && asset!.isNotEmpty);

  @override
  bool operator ==(Object other) =>
      other is ReplaceVideoProcessor &&
      other.asset == asset &&
      _sameBytes(other.bytes);

  bool _sameBytes(List<int>? other) {
    final mine = bytes;
    if (identical(mine, other)) {
      return true;
    }
    if (mine == null || other == null || mine.length != other.length) {
      return false;
    }
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(asset, bytes?.length);
}
