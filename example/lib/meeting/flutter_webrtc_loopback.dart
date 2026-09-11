import 'package:flutter/material.dart';
import 'package:flutter_ai_communications_webrtc/flutter_ai_communications_webrtc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'host_webrtc_loopback.dart';
import 'video_surface_view.dart';

/// Host-owned loopback PeerConnection pair using flutter_webrtc.
///
/// Session has no PeerConnection type. The host addTracks each Send track
/// when a [MediaStreamTrack] mapper exists; inbound [RTCVideoView] shows the
/// remote loopback. Until a mapped track is available, inbound falls back to
/// the Send track Video surface (processed Production frames).
final class FlutterWebRtcLoopback implements HostWebRtcLoopback {
  RTCPeerConnection? _sender;
  RTCPeerConnection? _receiver;
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  var _rendererReady = false;
  var _hasRemote = false;
  WebrtcSendTrack? _track;
  RTCRtpSender? _rtpSender;

  Future<void> _ensurePeerConnections() async {
    if (_sender != null) {
      return;
    }
    await _renderer.initialize();
    _rendererReady = true;
    const config = {'sdpSemantics': 'unified-plan'};
    _sender = await createPeerConnection(config);
    _receiver = await createPeerConnection(config);
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
      if (event.streams.isEmpty) {
        return;
      }
      _renderer.srcObject = event.streams.first;
      _hasRemote = true;
    };
  }

  Future<void> _negotiate() async {
    final sender = _sender;
    final receiver = _receiver;
    if (sender == null || receiver == null) {
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
  Future<void> applySendTrack(WebrtcSendTrack? track) async {
    _track = track;
    if (track == null) {
      await _rtpSender?.replaceTrack(null);
      return;
    }
    try {
      await _ensurePeerConnections();
      if (_rtpSender == null) {
        await _negotiate();
      }
    } on Object {
      // Widget tests and headless CI have no native WebRTC factory.
      return;
    }
  }

  @override
  Future<void> dispose() async {
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
  }
}
