# 06 — Join and enable-video-later

**What to build:** Join stops the lobby Session and starts a meeting Session
from Session settings (or copied capture/render/camera ids, mute, Camera-off).
Echo Transport / WebRTC plugin attaches only after the meeting Session is
ready. Audio-only join can enable video later on the same meeting Session.
Missing camera is Session status, not a failed start.

**Blocked by:** 05 — Lobby subsection; library ticket 02

**Status:** done (2026-09-01). Join is stop + start with Session settings; Echo Transport attaches only after meeting start.

- [ ] Lobby and meeting are different Session objects
- [ ] Copied picks stick on the meeting Session
- [ ] Enable-video-later does not replace the audio Capture stream
- [ ] Camera denied / none is shown from Session status; Session stays up
