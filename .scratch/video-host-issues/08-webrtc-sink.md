# 08 — Host Transport and flutter_webrtc sink

**What to build:** The host owns PeerConnection and signaling. After
StartReady or enableVideo it attaches the library flutter_webrtc sink and
addTrack. Detach on leave does not leak the camera.

**Blocked by:** 07 — In-session controls; library tickets 04 and 12

**Status:** ready-for-agent

- [ ] Session wrapper has no PeerConnection type
- [ ] Sink attach/detach is tested
- [ ] First slice may be example loopback with no product signaling
- [ ] Loopback or documented staging view shows processed frames
