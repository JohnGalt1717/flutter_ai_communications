import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_communications_webrtc/flutter_ai_communications_webrtc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'host_webrtc_loopback.dart';
import 'video_surface_view.dart';

/// Host-owned loopback PeerConnection pair using flutter_webrtc.
///
/// Session has no PeerConnection type. [mapSendTrack] turns a Send track into
/// a flutter_webrtc [MediaStreamTrack] for `addTrack`. Until that mapper
/// supplies a track, inbound falls back to the Send track Video surface.
final class FlutterWebRtcLoopback implements HostWebRtcLoopback {
  /// Optional host mapper from Send track to a MediaStreamTrack.
  FlutterWebRtcLoopback({this.mapSendTrack});

  /// Host `mapSendTrack`. Null until native Production-path bind exists.
  final Future<MediaStreamTrack?> Function(WebrtcSendTrack track)? mapSendTrack;

  RTCPeerConnection? _sender;
  RTCPeerConnection? _receiver;
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  var _rendererReady = false;
  var _hasRemote = false;
  var _disposed = false;
  WebrtcSendTrack? _track;
  RTCRtpSender? _rtpSender;
  Future<void> _queue = Future<void>.value();
  VoidCallback? _inboundChanged;

  @override
  set inboundChanged(VoidCallback? callback) {
    _inboundChanged = callback;
  }

  Future<void> _run(Future<void> Function() op) {
    _queue = _queue.then((_) async {
      if (_disposed) {
        return;
      }
      await op();
    });
    return _queue;
  }

  Future<void> _ensurePeerConnections() async {
    if (_sender != null || _disposed) {
      return;
    }
    await _renderer.initialize();
    if (_disposed) {
      await _renderer.dispose();
      return;
    }
    _rendererReady = true;
    const config = {'sdpSemantics': 'unified-plan'};
    _sender = await createPeerConnection(config);
    _receiver = await createPeerConnection(config);
    if (_disposed) {
      await _sender?.close();
      await _receiver?.close();
      _sender = null;
      _receiver = null;
      return;
    }
    _sender!.onIceCandidate = (candidate) {
      final receiver = _receiver;
      if (receiver != null && candidate.candidate != null) {
        receiver.addCandidate(candidate);
      }
    };
    _receiver!.onIceCandidate = (candidate) {
      final sender = _sender;
      if (sender != null && candidate.candidate != null) {
        sender.addCandidate(candidate);
      }
    };
    _receiver!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _renderer.srcObject = event.streams.first;
      }
      if (event.track != null || event.streams.isNotEmpty) {
        _hasRemote = true;
        _inboundChanged?.call();
      }
    };
  }

  Future<void> _negotiate() async {
    final sender = _sender;
    final receiver = _receiver;
    if (sender == null || receiver == null || _disposed) {
      return;
    }
    final offer = await sender.createOffer();
    await sender.setLocalDescription(offer);
    await receiver.setRemoteDescription(offer);
    final answer = await receiver.createAnswer();
    await receiver.setLocalDescription(answer);
    await sender.setRemoteDescription(answer);
  }

  @override
  Widget inboundView({Key? key}) {
    final keyOrDefault = key ?? inboundKey;
    if (_hasRemote && _rendererReady) {
      return RTCVideoView(_renderer, key: keyOrDefault);
    }
    final surface = _track?.surface;
    if (surface != null) {
      return VideoSurfaceView(
        key: keyOrDefault,
        surface: surface,
        viewTypePrefix: 'fac-camera',
      );
    }
    return ColoredBox(
      key: keyOrDefault,
      color: const Color(0xFF111118),
      child: const Center(
        child: Text(
          'Waiting for inbound',
          style: TextStyle(color: Color(0xFFB0B0C0)),
        ),
      ),
    );
  }

  @override
  Future<void> applySendTrack(WebrtcSendTrack? track) {
    return _run(() => _applySendTrack(track));
  }

  Future<void> _applySendTrack(WebrtcSendTrack? track) async {
    _track = track;
    if (track == null) {
      await _rtpSender?.replaceTrack(null);
      return;
    }
    try {
      await _ensurePeerConnections();
      if (_disposed) {
        return;
      }
      final mapped = await mapSendTrack?.call(track);
      if (mapped != null) {
        final sender = _sender;
        if (sender == null) {
          return;
        }
        if (_rtpSender == null) {
          _rtpSender = await sender.addTrack(mapped);
          await _negotiate();
        } else {
          await _rtpSender!.replaceTrack(mapped);
        }
      } else if (_rtpSender == null) {
        await _negotiate();
      }
    } on Object {
      // Widget tests and headless CI have no native WebRTC factory.
      return;
    }
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _run(() async {
      await _rtpSender?.replaceTrack(null);
      _rtpSender = null;
      _track = null;
      _hasRemote = false;
      _renderer.srcObject = null;
      await _sender?.close();
      await _receiver?.close();
      _sender = null;
      _receiver = null;
      if (_rendererReady) {
        await _renderer.dispose();
        _rendererReady = false;
      }
    });
  }
}
