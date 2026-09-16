import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

import 'camera_dom_chrome_stub.dart'
    if (dart.library.html) 'camera_dom_chrome_web.dart';

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
    this.caption,
    this.showMuteBadge = false,
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

  /// Optional name drawn on the tile (`You` on the meeting PIP).
  final String? caption;

  /// When true, draw a mute badge on the tile.
  final bool showMuteBadge;

  @override
  Widget build(BuildContext context) {
    final surface = this.surface;
    if (surface == null) {
      return placeholder ?? const ColoredBox(color: Color(0xFF111118));
    }
    // HtmlElementView on web must sit in a tight pixel box. LayoutBuilder /
    // AspectRatio inside ListView asserts in the viewport during mount.
    if (surface.kind == VideoSurfaceKind.htmlElement) {
      return _HtmlCameraSlot(
        viewType: '$viewTypePrefix-${surface.handle}',
        aspectRatio: surface.aspectRatio,
        caption: viewTypePrefix == 'fac-camera' ? caption : null,
        showMuteBadge:
            viewTypePrefix == 'fac-camera' ? showMuteBadge : false,
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
    final feed = _ContainedFeed(
      aspectRatio: aspect,
      child: Texture(textureId: surface.handle),
    );
    if (caption == null && !showMuteBadge) {
      return feed;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        feed,
        if (caption != null)
          Positioned(
            left: 8,
            bottom: 6,
            child: Text(
              caption!,
              style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 12),
            ),
          ),
        if (showMuteBadge)
          const Positioned(
            right: 6,
            top: 6,
            child: Icon(Icons.mic_off, size: 16, color: Color(0xFFFF8A80)),
          ),
      ],
    );
  }
}

final class _HtmlCameraSlot extends StatefulWidget {
  const _HtmlCameraSlot({
    required this.viewType,
    required this.aspectRatio,
    this.caption,
    this.showMuteBadge = false,
  });

  final String viewType;
  final double aspectRatio;
  final String? caption;
  final bool showMuteBadge;

  bool get _isCamera => viewType.startsWith('fac-camera-');

  @override
  State<_HtmlCameraSlot> createState() => _HtmlCameraSlotState();
}

final class _HtmlCameraSlotState extends State<_HtmlCameraSlot> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publishChrome();
  }

  @override
  void didUpdateWidget(_HtmlCameraSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _publishChrome();
  }

  @override
  void dispose() {
    if (widget._isCamera) {
      setCameraDomChrome();
    }
    super.dispose();
  }

  void _publishChrome() {
    if (!widget._isCamera) {
      return;
    }
    setCameraDomChrome(caption: widget.caption, muted: widget.showMuteBadge);
  }

  @override
  Widget build(BuildContext context) {
    return _ContainedFeed(
      aspectRatio: widget.aspectRatio,
      child: ClipRect(
        child: HtmlElementView(viewType: widget.viewType),
      ),
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
