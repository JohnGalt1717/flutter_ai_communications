import 'dart:async';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';

import 'webrtc_send_track.dart';

/// Transport plugin Video sink. Host owns PeerConnection and signaling.
///
/// Attach after StartReady or enableVideo. Local Texture preview uses
/// [Session.videoSurface] and does not need this package. This type does
/// not create a PeerConnection.
final class WebrtcVideoSink implements VideoSink {
  /// Creates a Video sink that yields [WebrtcSendTrack]s.
  WebrtcVideoSink() {
    _localVideos.onListen = () {
      if (!_localVideos.isClosed) {
        _localVideos.add(_localVideo);
      }
    };
  }

  Session? _session;
  VideoPathSnapshot? _lastPath;
  WebrtcSendTrack? _localVideo;
  final StreamController<WebrtcSendTrack?> _localVideos =
      StreamController<WebrtcSendTrack?>.broadcast();

  /// Current Send track. Null while Camera-off or detached.
  WebrtcSendTrack? get localVideo => _localVideo;

  /// Send track updates. Late subscribers receive the current track.
  Stream<WebrtcSendTrack?> get localVideos => _localVideos.stream;

  /// Last Production video path snapshot.
  VideoPathSnapshot? get lastPath => _lastPath;

  /// Attaches to [session]. Detaches a previous Session first.
  void attach(Session session) {
    if (!identical(_session, session)) {
      detach();
      _session = session;
    }
    session.attachVideoSink(this);
  }

  /// Detaches. Idempotent. Does not end the Session or replace capture.
  void detach() {
    final session = _session;
    _session = null;
    if (session != null && !session.isStopped) {
      session.detachVideoSink(this);
    }
    _lastPath = null;
    _publish(null);
  }

  @override
  void onVideoPath(VideoPathSnapshot snapshot) {
    _lastPath = snapshot;
    if (snapshot.cameraOff) {
      _publish(null);
      return;
    }
    _publish(
      WebrtcSendTrack(
        id: 'video-${snapshot.generation}',
        generation: snapshot.generation,
        muteVideo: snapshot.muteVideo,
        processor: snapshot.processor,
        surface: snapshot.surface,
      ),
    );
  }

  void _publish(WebrtcSendTrack? track) {
    if (_localVideo == track) {
      return;
    }
    _localVideo = track;
    if (!_localVideos.isClosed) {
      _localVideos.add(track);
    }
  }
}
