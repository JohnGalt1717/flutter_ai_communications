# 07 — In-session AV controls

**What to build:** In-call mute-audio, mute-video, Camera-off, switch camera,
processor, audio route, pause, and stop. Mute-video is not Camera-off.

**Blocked by:** 06 — Join, promote, enable-video-later

**Status:** done (2026-09-01). Example keys: mute, mute-video, camera-off, live camera pick, pause, stop.

- [ ] Controls match the host narrative table
- [ ] Separate view-model methods for mute-video and Camera-off
- [ ] Pause parks both sides without destroying Session
- [ ] Stop ends Session and releases the camera
- [ ] Marionette keys exist for each control
