import 'dart:typed_data';

/// One native JPEG/PNG sample of a Production video path.
final class StillFrame {
  /// Creates a still sampled from a Production video path.
  const StillFrame({
    required this.bytes,
    required this.width,
    required this.height,
    this.mime = 'image/jpeg',
  });

  /// Encoded still bytes.
  final Uint8List bytes;

  /// Pixel width of the sampled frame.
  final int width;

  /// Pixel height of the sampled frame.
  final int height;

  /// `image/jpeg` or `image/png`.
  final String mime;

  /// Reads a method-channel map. Null when the path is not feeding.
  static StillFrame? fromChannel(Object? value) {
    if (value is! Map) {
      return null;
    }
    final map = Map<Object?, Object?>.from(value);
    final raw = map['bytes'];
    final bytes = switch (raw) {
      Uint8List b => b,
      List<int> list => Uint8List.fromList(list),
      _ => null,
    };
    final width = map['width'];
    final height = map['height'];
    if (bytes == null || bytes.isEmpty || width is! int || height is! int) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    final mime = map['mime'];
    return StillFrame(
      bytes: bytes,
      width: width,
      height: height,
      mime: mime is String && mime.isNotEmpty ? mime : 'image/jpeg',
    );
  }
}
