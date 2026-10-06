import 'dart:async';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';

import 'webrtc_send_track.dart';

/// Transport plugin Video sink. Host owns PeerConnection and signaling.
///
/// Attach after StartReady or enableVideo. Local Texture preview uses
/// [Session.videoSurface] and does not need this package. This type does
/// not create a PeerConnection. Screen send is a second Send track on
/// [localScreens].
final class WebrtcVideoSink implements VideoSink, ScreenVideoSink {
  /// Creates a Video sink that yields [WebrtcSendTrack]s.
  WebrtcVideoSink() {
    _localVideos.onListen = () {
      if (!_localVideos.isClosed) {
        _localVideos.add(_localVideo);
      }
    };
    _localScreens.onListen = () {
      if (!_localScreens.isClosed) {
        _localScreens.add(_localScreen);
      }
    };
  }

  Session? _session;
  VideoPathSnapshot? _lastPath;
  VideoPathSnapshot? _lastScreenPath;
  WebrtcSendTrack? _localVideo;
  WebrtcSendTrack? _localScreen;
  final StreamController<WebrtcSendTrack?> _localVideos =
      StreamController<WebrtcSendTrack?>.broadcast();
  final StreamController<WebrtcSendTrack?> _localScreens =
      StreamController<WebrtcSendTrack?>.broadcast();

  /// Current camera Send track. Null while Camera-off or detached.
  WebrtcSendTrack? get localVideo => _localVideo;

  /// Camera Send track updates. Late subscribers receive the current track.
  Stream<WebrtcSendTrack?> get localVideos => _localVideos.stream;

  /// Current screen Send track. Null while screen send is not running.
  WebrtcSendTrack? get localScreen => _localScreen;

  /// Screen Send track updates. Late subscribers receive the current track.
  Stream<WebrtcSendTrack?> get localScreens => _localScreens.stream;

  /// Last camera Production video path snapshot.
  VideoPathSnapshot? get lastPath => _lastPath;

  /// Last screen-send Production video path snapshot.
  VideoPathSnapshot? get lastScreenPath => _lastScreenPath;

  /// Attaches to [session]. Detaches a previous Session first.
  void attach(Session session) {
    if (!identical(_session, session)) {
      detach();
      _session = session;
    }
    session.attachVideoSink(this);
    session.attachScreenVideoSink(this);
  }

  /// Detaches. Idempotent. Does not end the Session or replace capture.
  void detach() {
    final session = _session;
    _session = null;
    if (session != null && !session.isStopped) {
      session.detachVideoSink(this);
      session.detachScreenVideoSink(this);
    }
    _lastPath = null;
    _lastScreenPath = null;
    _publish(null);
    _publishScreen(null);
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

  @override
  void onScreenVideoPath(VideoPathSnapshot snapshot) {
    _lastScreenPath = snapshot;
    if (snapshot.cameraOff) {
      _publishScreen(null);
      return;
    }
    _publishScreen(
      WebrtcSendTrack(
        id: 'screen-${snapshot.generation}',
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

  void _publishScreen(WebrtcSendTrack? track) {
    if (_localScreen == track) {
      return;
    }
    _localScreen = track;
    if (!_localScreens.isClosed) {
      _localScreens.add(track);
    }
  }
}
