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
  });

  /// Surface to render, or null for [placeholder].
  final VideoSurface? surface;

  /// Prefix for web HtmlElementView types (`fac-camera`, `fac-screen`).
  final String viewTypePrefix;

  /// Shown when [surface] is null.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final surface = this.surface;
    if (surface == null) {
      return placeholder ?? const ColoredBox(color: Color(0xFF111118));
    }
    if (surface.kind == VideoSurfaceKind.htmlElement) {
      return ClipRect(
        child: HtmlElementView(viewType: '$viewTypePrefix-${surface.handle}'),
      );
    }
    return Texture(textureId: surface.handle);
  }
}
