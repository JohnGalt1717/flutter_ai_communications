import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host widget for one [VideoSurface].
///
/// Texture id on most platforms; HtmlElementView on web. Callers do not
/// import `RTCVideoView` for local send. Inbound WebRTC views stay host
/// PeerConnection code.
final class const VideoSurfaceView({
  super.key,
  required final VideoSurface? surface,
  required final String viewTypePrefix,
  final Widget? placeholder,
}) extends StatelessWidget {
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
