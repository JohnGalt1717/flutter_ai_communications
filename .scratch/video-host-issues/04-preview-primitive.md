# 04 — Unbranded Preview Texture primitive

**What to build:** A widget that hosts the library Preview Texture id.
Preview start/stop/selectCamera/setProcessor/setCameraEnabled run on the
idle manager. No branded lobby layout in a helper widget.

**Blocked by:** 02 — Audio manager; library ticket 03

**Status:** done (2026-09-01). Example `self-view` renders the Session Video surface Texture.

- [ ] Preview works with no Session
- [ ] Widget test accepts a fake texture id
- [ ] Camera-off in preview does not call `session.stop`
- [ ] Helper does not ship Teams or Zoom chrome
