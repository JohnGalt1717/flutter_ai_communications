# 08 — Host Transport and flutter_webrtc sink

**What to build:** The host owns PeerConnection and signaling. After
StartReady or enableVideo it attaches the library flutter_webrtc sink and
addTrack. Detach on leave does not leak the camera.

**Blocked by:** 07 — In-session controls; library tickets 04 and 12 (done)

**Status:** partial (2026-09-04). Library #46 / #48 on `main`. Example meeting
Join attaches `WebrtcVideoSink` (`webrtc-send-track`). Echo Transport remains
the audio stand-in. Example loopback meeting chrome (`loopback-meeting`)
renders Session Video surfaces (camera + screen) with no signaling.
Remaining: host addTrack + RTCVideoView inbound. Native
`attachProductionVideoPathNative` is still a no-op, so a PeerConnection
cannot show Production frames yet.

- [x] Session wrapper has no PeerConnection type
- [x] Sink attach/detach is tested (library package + example Join)
- [x] First slice may be example loopback with no product signaling
- [x] Documented staging view: `docs/host-webrtc-narrative.md`
- [ ] Loopback RTCVideoView shows processed frames
