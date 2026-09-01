# 03 — Lobby Session

**What to build:** A host can start a lobby Session with no Transport plugin, show a Video surface, pick devices, Mute, Camera-off, then Join by stopping that Session and starting a meeting Session with Session settings (or copied start args). Lobby does not occupy a second Session slot; alreadyActive still holds. Camera preview is not used in the lobby.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** done (2026-09-01). Lobby is a Session; Join is stop + start with Session settings.

- [x] `start(purpose: lobby)` works with no Transport plugin
- [x] Capture stream is the lobby meter; no second audio graph
- [x] Join is stop + start; objects are not shared
- [x] Leaving the lobby is `session.stop`
- [x] Example lobby subsection can be driven by Orchestration
