# 02 — Session and platform-interface video contracts

**What to build:** A host can, against a fake platform adapter, enumerate cameras, start an AV or audio-only Session, enable video later, select another camera, Mute-video (path stays live), Camera-off (path not fed), pause both sides, and read a Preview Texture id. Audio capture stream identity does not change when video attaches. New Start results cover camera denied / restricted / no usable camera. Existing audio adapters still load because new platform methods default to unimplemented.

**Blocked by:** 01 — Shared video types

**Status:** ready-for-agent

- [ ] Fake-adapter tests cover every new Start result
- [ ] One live Session still holds
- [ ] Mid-session camera picks do not write Camera preference
- [ ] Enable-video-later does not replace the audio Capture stream
- [ ] Mute-video and Camera-off are distinct and tested
- [ ] No flutter_webrtc types in the app or platform_interface packages
