# Changelog

## Unreleased

* `processWebrtcVideoTrack`: runs the Video processor on a host flutter_webrtc camera track in place; fails closed to black frames (#113, ADR-0032).

## 0.0.1

* Video sink that yields Send tracks. Host owns PeerConnection and signaling.
