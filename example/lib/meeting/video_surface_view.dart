import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host widget for one [VideoSurface].
///
/// Texture id on most platforms; HtmlElementView on web. Callers do not
/// import `RTCVideoView` for local send. Inbound WebRTC views stay host
/// PeerConnection code.
final class VideoSurfaceView extends StatelessWidget {
  /// Creates a host Video surface widget.
  const VideoSurfaceView({
    super.key,
    required this.surface,
    required this.viewTypePrefix,
    this.placeholder,
    this.pixelWidth,
    this.pixelHeight,
    this.fit = BoxFit.cover,
  });

  /// Surface to render, or null for [placeholder].
  final VideoSurface? surface;

  /// Prefix for web HtmlElementView types (`fac-camera`, `fac-screen`).
  final String viewTypePrefix;

  /// Shown when [surface] is null.
  final Widget? placeholder;

  /// Native frame width. Used with [pixelHeight] to keep aspect ratio.
  final int? pixelWidth;

  /// Native frame height.
  final int? pixelHeight;

  /// How the native frame fills the widget. Cover matches in-call tiles.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final surface = this.surface;
    if (surface == null) {
      return placeholder ?? const ColoredBox(color: Color(0xFF111118));
    }
    final Widget child;
    if (surface.kind == VideoSurfaceKind.htmlElement) {
      child = HtmlElementView(viewType: '$viewTypePrefix-${surface.handle}');
    } else {
      child = Texture(textureId: surface.handle);
    }
    final width = pixelWidth;
    final height = pixelHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return ClipRect(child: child);
    }
    return FittedBox(
      fit: fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: child,
      ),
    );
  }
}
