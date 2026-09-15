/// How a Video surface handle is interpreted by the host widget.
enum VideoSurfaceKind {
  /// Flutter Texture registry id.
  texture,

  /// Web HtmlElementView / platform view id.
  htmlElement,
}

/// Flutter-visible surface for local send or one inbound stream.
final class VideoSurface {
  /// Creates a Video surface.
  const VideoSurface({
    required this.handle,
    this.kind = VideoSurfaceKind.texture,
    this.width,
    this.height,
    this.quarterTurns = 0,
  });

  /// Texture id or view/element id.
  final int handle;

  /// How [handle] is bound in the host widget.
  final VideoSurfaceKind kind;

  /// Raster width in pixels, when the graph reported it.
  final int? width;

  /// Raster height in pixels, when the graph reported it.
  final int? height;

  /// Clockwise 90° turns reported by native. Host layout does not apply this
  /// to already-upright Camera2 rasters (that turned the picture 90°).
  final int quarterTurns;

  /// Pixel-buffer width / height. Missing size is 16:9.
  double get rasterAspect {
    final width = this.width;
    final height = this.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  /// Width / height of the raster. Prefer [displayAspectRatio] for layout.
  double get aspectRatio => rasterAspect;

  /// Tile aspect for the current UI: portrait is the portrait-shaped raster
  /// (9:16 for a 16:9 Android buffer, native 9:16 on iOS). Landscape is the
  /// landscape-shaped raster. The picture is never rotated in the host.
  double displayAspectRatio({required bool portrait}) {
    final raster = rasterAspect;
    if (portrait) {
      return raster <= 1 ? raster : 1 / raster;
    }
    return raster >= 1 ? raster : 1 / raster;
  }

  /// True when a 16:9 raster is shown in a 9:16 tile (crop, don't rotate).
  bool displayCoversRaster({required bool portrait}) {
    return (displayAspectRatio(portrait: portrait) - rasterAspect).abs() > 0.02;
  }

  @override
  bool operator ==(Object other) =>
      other is VideoSurface &&
      other.handle == handle &&
      other.kind == kind &&
      other.width == width &&
      other.height == height &&
      other.quarterTurns == quarterTurns;

  @override
  int get hashCode => Object.hash(handle, kind, width, height, quarterTurns);
}
