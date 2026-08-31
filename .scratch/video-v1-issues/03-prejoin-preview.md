# 03 — Lobby Session

**What to build:** A host can start a lobby Session with no Transport plugin, show a Video surface, pick devices, Mute, Camera-off, then Join by stopping that Session and starting a meeting Session with Session settings (or copied start args). Lobby does not occupy a second Session slot; alreadyActive still holds. Camera preview is not used in the lobby.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** ready-for-agent

- [ ] `start(purpose: lobby)` works with no Transport plugin
- [ ] Capture stream is the lobby meter; no second audio graph
- [ ] Join is stop + start; objects are not shared
- [ ] Leaving the lobby is `session.stop`
- [ ] Example lobby subsection can be driven by Orchestration
