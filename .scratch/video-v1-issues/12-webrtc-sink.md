# 12 — flutter_webrtc sink package

**What to build:** A companion workspace package attaches as a Video sink and yields a MediaStreamTrack (or equivalent) the host adds to its own PeerConnection. Session still has no flutter_webrtc types. Signaling stays in the host.

**Blocked by:** 04 — Video sink provider seam; 05 — iOS camera graph (or any one native graph)

**Status:** ready-for-agent

- [ ] Host can attach the sink after StartReady or enableVideo
- [ ] Local Texture preview works without this package
- [ ] Example loopback or documented sample shows processed frames on an RTCVideoView
- [ ] Package does not create PeerConnections
