# 05 — Example lobby subsection

**What to build:** The example lobby follows `docs/host-prejoin-narrative.md`:
mode, audio picks, camera pick when present, self-view, mute, Join,
leave-without-join. Mimic the best of Zoom/Teams: large self-view, device
picks on one row, permission on enter.

Overlaps library ticket `13`. Do not build a second lobby.

**Blocked by:** 03 — Preference persistence (camera when it exists)

**Status:** done (2026-09-01). Example lobby subsection is the Orchestration path. Host preference persistence (ticket 03) is still open.

- [ ] Lobby is a Session (`purpose: lobby`), no Transport plugin
- [ ] Join uses current picks via Session settings or copied start args
- [ ] Leave-without-join only stops the lobby Session
- [ ] Orchestration keys exist for lobby controls
