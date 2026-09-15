import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host widget for one [VideoSurface].
///
/// Texture id on most platforms; HtmlElementView on web. Callers do not
/// import `RTCVideoView` for local send. Inbound WebRTC views stay host
/// PeerConnection code. The feed is always contained — never stretched.
final class VideoSurfaceView extends StatelessWidget {
  /// Creates a host Video surface widget.
  const VideoSurfaceView({
    super.key,
    required this.surface,
    required this.viewTypePrefix,
    this.placeholder,
    this.followUiOrientation = false,
  });

  /// Surface to render, or null for [placeholder].
  final VideoSurface? surface;

  /// Prefix for web HtmlElementView types (`fac-camera`, `fac-screen`).
  final String viewTypePrefix;

  /// Shown when [surface] is null.
  final Widget? placeholder;

  /// When true, the tile is portrait-shaped in portrait UI and
  /// landscape-shaped in landscape UI (iOS Camera and Android Camera2
  /// upright rasters). Screen send leaves this false so 16:9 stays 16:9.
  final bool followUiOrientation;

  @override
  Widget build(BuildContext context) {
    final surface = this.surface;
    if (surface == null) {
      return placeholder ?? const ColoredBox(color: Color(0xFF111118));
    }
    // HtmlElementView on web must sit in a tight pixel box. LayoutBuilder /
    // AspectRatio inside ListView asserts in the viewport during mount.
    if (surface.kind == VideoSurfaceKind.htmlElement) {
      const width = 320.0;
      final height = width / surface.aspectRatio;
      return SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: HtmlElementView(viewType: '$viewTypePrefix-${surface.handle}'),
        ),
      );
    }
    // Texture fills its layout size and ignores FittedBox / RotatedBox.
    // Camera tiles follow the UI orientation so a landscape session is a
    // wide box (iOS RotationCoordinator already reports 16:9; Android
    // Camera2 rasters catch up on cameraFormat).
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final aspect = followUiOrientation
        ? surface.displayAspectRatio(portrait: portrait)
        : surface.rasterAspect;
    return _ContainedFeed(
      aspectRatio: aspect,
      child: Texture(textureId: surface.handle),
    );
  }
}

final class _ContainedFeed extends StatelessWidget {
  const _ContainedFeed({required this.aspectRatio, required this.child});

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final widthBounded = maxWidth.isFinite;
        final heightBounded = maxHeight.isFinite;
        final Size box;
        if (widthBounded && heightBounded) {
          box = applyBoxFit(
            BoxFit.contain,
            Size(aspectRatio, 1),
            Size(maxWidth, maxHeight),
          ).destination;
        } else if (widthBounded) {
          box = Size(maxWidth, maxWidth / aspectRatio);
        } else if (heightBounded) {
          box = Size(maxHeight * aspectRatio, maxHeight);
        } else {
          box = Size(aspectRatio * 720, 720);
        }
        return Align(
          child: SizedBox(width: box.width, height: box.height, child: child),
        );
      },
    );
  }
}
