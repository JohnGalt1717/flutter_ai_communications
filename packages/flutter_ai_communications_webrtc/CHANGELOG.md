# Changelog

## Unreleased

* `processWebrtcVideoTrack`: runs the Video processor on a host flutter_webrtc camera track in place; fails closed to black frames (#113, ADR-0032).
* `webrtcTrackProcessingUnavailable` (Android): track ids whose processor gave up mid-call (5 failed segmentations in a row) or turned out not to be on the camera path, so the host can say video is paused.
* Android refuses a track whose processor flutter_webrtc never runs (shared or re-wrapped camera track) with `unavailable`, after watching its first frames.
* `ReplaceVideoProcessor(asset:)` is loaded to bytes before it reaches native code.
* Requires flutter_webrtc `>=1.6.2 <1.7.0`.

## 0.0.1

* Video sink that yields Send tracks. Host owns PeerConnection and signaling.
