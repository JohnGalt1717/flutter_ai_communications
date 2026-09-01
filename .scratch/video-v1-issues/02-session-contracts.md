# 02 — Session and platform-interface video contracts

**What to build:** A host can, against a fake platform adapter, enumerate cameras, start an AV or audio-only Session, enable video later, select another camera, Mute-video (path stays live), Camera-off (path not fed), pause both sides, and read a Preview Texture id. Audio capture stream identity does not change when video attaches. New Start results cover camera denied / restricted / no usable camera. Existing audio adapters still load because new platform methods default to unimplemented.

**Blocked by:** 01 — Shared video types

**Status:** done (2026-09-01). Fake-platform Session video contracts on `main`.

- [x] Fake-adapter tests cover every new Start result
- [x] One live Session still holds
- [x] Mid-session camera picks do not write Camera preference
- [x] Enable-video-later does not replace the audio Capture stream
- [x] Mute-video and Camera-off are distinct and tested
- [x] No flutter_webrtc types in the app or platform_interface packages
