import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_webrtc/flutter_ai_communications_webrtc.dart';

import 'video_surface_view.dart';

/// Host-owned loopback PeerConnection. Session has no PeerConnection type.
///
/// The host `addTrack`s each [WebrtcSendTrack] and renders inbound video
/// with [RTCVideoView] (or a test double). Detach does not end the Session.
abstract interface class HostWebRtcLoopback {
  /// Inbound video tile. Key [inboundKey] for the Orchestration harness.
  Widget inboundView({Key? key});

  /// Adds, replaces, or removes the Send track on the host PeerConnection.
  Future<void> applySendTrack(WebrtcSendTrack? track);

  /// Tears down PeerConnections. Does not stop the Session.
  Future<void> dispose();
}

/// Harness key for the inbound WebRTC tile.
const inboundKey = Key('webrtc-inbound');

/// In-memory loopback for tests. Does not construct a native PeerConnection.
final class FakeHostWebRtcLoopback implements HostWebRtcLoopback {
  /// Last Send track passed to [applySendTrack].
  WebrtcSendTrack? lastTrack;

  /// Send track ids that were added.
  final addedTrackIds = <String>[];

  /// Send track ids that were removed.
  final removedTrackIds = <String>[];

  /// Whether [dispose] ran.
  var disposed = false;

  @override
  Widget inboundView({Key? key}) {
    final track = lastTrack;
    if (track == null || track.surface == null) {
      return ColoredBox(
        key: key ?? inboundKey,
        color: const Color(0xFF111118),
        child: const Center(
          child: Text(
            'Waiting for inbound',
            style: TextStyle(color: Color(0xFFB0B0C0)),
          ),
        ),
      );
    }
    return VideoSurfaceView(
      key: key ?? inboundKey,
      surface: track.surface,
      viewTypePrefix: 'fac-camera',
    );
  }

  @override
  Future<void> applySendTrack(WebrtcSendTrack? track) async {
    final previous = lastTrack;
    if (previous != null && (track == null || track.id != previous.id)) {
      removedTrackIds.add(previous.id);
    }
    if (track != null && track.id != previous?.id) {
      addedTrackIds.add(track.id);
    }
    lastTrack = track;
  }

  @override
  Future<void> dispose() async {
    if (lastTrack != null) {
      removedTrackIds.add(lastTrack!.id);
    }
    lastTrack = null;
    disposed = true;
  }
}
