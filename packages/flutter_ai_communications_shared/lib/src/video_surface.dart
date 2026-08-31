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
  const VideoSurface({required this.handle, this.kind = VideoSurfaceKind.texture});

  /// Texture id or view/element id.
  final int handle;

  /// How [handle] is bound in the host widget.
  final VideoSurfaceKind kind;

  @override
  bool operator ==(Object other) =>
      other is VideoSurface && other.handle == handle && other.kind == kind;

  @override
  int get hashCode => Object.hash(handle, kind);
}
