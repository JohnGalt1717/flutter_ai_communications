# 04 — Video sink provider seam

**What to build:** A host can attach and detach one or more Video sinks on a Session (and document the same hook for preview if needed). A fake sink observes generation, mute-video, Camera-off, and processor identity. Detach does not end the Session or replace audio streams. The native hook is documented so a later flutter_webrtc or disk package can bind.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** done (2026-09-03). GitHub #45, PR #46 (`e207769`). `Session.attachVideoSink` / `detachVideoSink`; native hook `attachProductionVideoPathNative`.

- [x] Two fake sinks can attach at once
- [x] Mute-video and Camera-off notify sinks differently
- [x] Detach is idempotent
- [x] Session API has no PeerConnection or MediaStream types
