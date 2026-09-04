import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

import 'video_surface_view.dart';

/// Teams-like loopback meeting chrome.
///
/// Media stays on this device: local camera and screen Video surfaces are
/// the participant and content stage. Echo Transport and the WebRTC sink
/// attach in the host; nothing is signaled off-box.
final class LoopbackMeetingStage extends StatelessWidget {
  /// Creates the loopback meeting stage.
  const LoopbackMeetingStage({
    super.key,
    required this.session,
    this.webrtcTrackId,
  });

  /// Live meeting Session.
  final Session session;

  /// Send track id from the WebRTC sink, if any.
  final String? webrtcTrackId;
  bool get _cameraLive =>
      session.cameraSend &&
      session.isCameraEnabled &&
      !session.isVideoMuted &&
      session.videoSurface != null;

  bool get _webCamera =>
      session.videoSurface?.kind == VideoSurfaceKind.htmlElement;

  @override
  Widget build(BuildContext context) {
    final sharing = session.isScreenSending;
    return ColoredBox(
      key: const Key('loopback-meeting'),
      color: const Color(0xFF0B0B10),
      child: Stack(
        children: [
          Positioned.fill(child: _stage(sharing)),
          Positioned(
            right: 12,
            bottom: 12,
            width: 168,
            height: 108,
            child: _pip(),
          ),
          Positioned(left: 12, top: 12, child: _rosterChip(sharing)),
          if (webrtcTrackId != null)
            Positioned(
              right: 12,
              top: 12,
              child: Text(
                webrtcTrackId!,
                key: const Key('webrtc-send-track'),
                style: const TextStyle(color: Color(0xFFB0B0C0), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stage(bool sharing) {
    if (sharing) {
      return _labeled(
        label: 'Screen',
        child: VideoSurfaceView(
          key: const Key('screen-loopback'),
          surface: session.screenSurface,
          viewTypePrefix: 'fac-screen',
          placeholder: _placeholder(
            session.screenUnavailableReason ?? 'Not sharing',
          ),
        ),
      );
    }
    if (_cameraLive && !_webCamera) {
      return _labeled(
        label: 'Loopback',
        child: VideoSurfaceView(
          key: const Key('loopback-tile'),
          surface: session.videoSurface,
          viewTypePrefix: 'fac-camera',
        ),
      );
    }
    if (_cameraLive && _webCamera) {
      return _labeled(
        label: 'Loopback',
        child: _placeholder(
          'Loopback · same camera surface',
          key: const Key('loopback-tile'),
        ),
      );
    }
    return _placeholder(
      session.videoUnavailableReason ??
          (session.isVideoMuted ? 'Video muted' : 'Camera off'),
      key: const Key('loopback-tile'),
    );
  }

  Widget _pip() {
    final live = _cameraLive;
    return DecoratedBox(
      key: const Key('self-view'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A48)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (live)
              VideoSurfaceView(
                surface: session.videoSurface,
                viewTypePrefix: 'fac-camera',
              )
            else
              _placeholder(
                session.videoUnavailableReason ??
                    (session.isVideoMuted ? 'Video muted' : 'Camera off'),
              ),
            const Positioned(
              left: 8,
              bottom: 6,
              child: Text(
                'You',
                style: TextStyle(color: Color(0xFFE8E8F0), fontSize: 12),
              ),
            ),
            if (session.isMuted)
              const Positioned(
                right: 6,
                top: 6,
                child: Icon(Icons.mic_off, size: 16, color: Color(0xFFFF8A80)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rosterChip(bool sharing) {
    final count = 1 + (sharing ? 1 : 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC1C1C28),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          '$count in this meeting · loopback',
          style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 12),
        ),
      ),
    );
  }

  Widget _labeled({required String label, required Widget child}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 12,
          bottom: 12,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _placeholder(String message, {Key? key}) {
    return ColoredBox(
      color: const Color(0xFF111118),
      child: Center(
        child: Text(
          message,
          key: key,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFB0B0C0)),
        ),
      ),
    );
  }
}

/// In-call control bar. Keys match the Orchestration harness.
final class MeetingBar extends StatelessWidget {
  /// Creates the in-call bar.
  const MeetingBar({
    super.key,
    required this.session,
    required this.onMute,
    required this.onCamera,
    required this.onMuteVideo,
    required this.onShare,
    required this.onStopShare,
    required this.onPause,
    required this.onLeave,
    required this.onProve,
  });

  /// Live meeting Session.
  final Session session;

  /// Mute / unmute.
  final VoidCallback onMute;

  /// Camera-off / camera on.
  final VoidCallback onCamera;

  /// Mute-video / unmute video.
  final VoidCallback onMuteVideo;

  /// Start screen send.
  final VoidCallback onShare;

  /// Stop screen send.
  final VoidCallback onStopShare;

  /// Pause / resume.
  final VoidCallback onPause;

  /// End the Session.
  final VoidCallback onLeave;

  /// Digital echo Prove.
  final VoidCallback onProve;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF16161F),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              key: const Key('meeting-bar'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _round(
                  key: const Key('mute'),
                  tooltip: session.isMuted ? 'Unmute' : 'Mute',
                  icon: session.isMuted ? Icons.mic_off : Icons.mic,
                  active: session.isMuted,
                  onPressed: onMute,
                ),
                _round(
                  key: const Key('camera-off'),
                  tooltip: session.isCameraEnabled ? 'Camera off' : 'Camera on',
                  icon: session.isCameraEnabled
                      ? Icons.videocam
                      : Icons.videocam_off,
                  active: !session.isCameraEnabled,
                  onPressed: onCamera,
                ),
                _round(
                  key: const Key('mute-video'),
                  tooltip: session.isVideoMuted ? 'Unmute video' : 'Mute video',
                  icon: session.isVideoMuted
                      ? Icons.video_camera_front_outlined
                      : Icons.video_camera_front,
                  active: session.isVideoMuted,
                  onPressed: session.isCameraEnabled ? onMuteVideo : null,
                ),
                _round(
                  key: const Key('screen-share'),
                  tooltip: 'Share',
                  icon: Icons.present_to_all,
                  active: session.isScreenSending,
                  onPressed: session.isScreenSending ? null : onShare,
                ),
                _round(
                  key: const Key('screen-stop'),
                  tooltip: 'Stop share',
                  icon: Icons.stop_screen_share_outlined,
                  onPressed: session.isScreenSending ? onStopShare : null,
                ),
                _round(
                  key: const Key('pause'),
                  tooltip: session.isPaused ? 'Resume' : 'Pause',
                  icon: session.isPaused ? Icons.play_arrow : Icons.pause,
                  active: session.isPaused,
                  onPressed: onPause,
                ),
                _round(
                  key: const Key('prove'),
                  tooltip: 'Prove',
                  icon: Icons.verified_outlined,
                  onPressed: onProve,
                ),
                _round(
                  key: const Key('stop'),
                  tooltip: 'Leave',
                  icon: Icons.call_end,
                  danger: true,
                  onPressed: onLeave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _round({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool active = false,
    bool danger = false,
  }) {
    final background = danger
        ? const Color(0xFFC4314B)
        : active
        ? const Color(0xFFE8E8F0)
        : const Color(0xFF2B2B38);
    final foreground = danger
        ? Colors.white
        : active
        ? const Color(0xFF1C1C28)
        : const Color(0xFFE8E8F0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: IconButton.filled(
          key: key,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: const Color(0xFF2B2B38),
            disabledForegroundColor: const Color(0xFF6E6E7A),
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

/// Host-owned Isolation prompt. Library events carry no copy.
final class IsolationBanner extends StatelessWidget {
  /// Creates a host Isolation prompt.
  const IsolationBanner({super.key, required this.event, required this.onOpen});

  /// Isolation event from the Session.
  final IsolationEvent event;

  /// Opens the system Isolation UI.
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    if (event.state != IsolationState.required) {
      return const SizedBox.shrink();
    }
    return Material(
      color: const Color(0xFF3A2A10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Voice Isolation is off. Open system microphone mode, or '
                'continue with a higher sound floor.',
              ),
            ),
            TextButton(
              key: const Key('open-isolation'),
              onPressed: onOpen,
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Host copy for a typed [StartResult] failure. Status code stays on `status`.
String? startFailureCopy(String? status) => switch (status) {
  'denied' =>
    'Microphone permission was declined. Enter lobby to approve and retry.',
  'restricted' => 'Microphone is restricted on this device.',
  'unavailable' => 'No usable capture Endpoint is available.',
  'alreadyActive' => 'A Session is already live. End it first.',
  'failed' => 'Session start failed. Check permission and try again.',
  'join-failed' => 'Join failed. Enter lobby and try again.',
  _ => null,
};
