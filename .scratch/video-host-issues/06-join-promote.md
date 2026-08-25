# 06 — Join, promote, enable-video-later

**What to build:** `start()` promotes or overrides preview. After StartReady
the Session owns the Texture. Audio-only join can enable video later on the
same Session. Camera denial is a typed Start result.

**Blocked by:** 05 — Landing page; library ticket 02

**Status:** ready-for-agent

- [ ] Unchanged camera/processor does not flicker on promote
- [ ] Override at start sticks
- [ ] Enable-video-later does not replace audio streams
- [ ] Denied / restricted / no usable camera are handled in UI
