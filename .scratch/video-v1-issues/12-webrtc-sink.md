# 12 — flutter_webrtc sink package

**What to build:** A companion workspace package attaches as a Video sink and yields a MediaStreamTrack (or equivalent) the host adds to its own PeerConnection. Session still has no flutter_webrtc types. Signaling stays in the host.

**Blocked by:** 04 — Video sink provider seam; 05 — iOS camera graph (or any one native graph)

**Status:** done (2026-09-03). GitHub #47, PR #48 (`4f38598`). Package
`flutter_ai_communications_webrtc`; documented sample in
`docs/host-webrtc-narrative.md`.

- [x] Host can attach the sink after StartReady or enableVideo
- [x] Local Texture preview works without this package
- [x] Example loopback or documented sample shows processed frames on an RTCVideoView
- [x] Package does not create PeerConnections
