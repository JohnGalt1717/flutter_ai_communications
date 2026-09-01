# 13 — Example lobby and in-session AV harness

**What to build:** The example has a Zoom/Teams-class **lobby subsection**: mode, mic and speaker picks, permission via `start()`, mute, Join, leave-without-join. Lobby is a Session with no Transport plugin. Join stops it and starts a meeting Session, then attaches Echo Transport (later the WebRTC plugin). In-session: mute, mute-video, Camera-off, live camera flip, pause, stop. Orchestration drives lobby → join → controls. Not a SignalR client.

**Blocked by:** 03 — Lobby Session; 05 — iOS camera graph (or first native graph available to the runner). Audio-only lobby Orchestration can land once 03 exists; the example audio lobby can land against today’s Session.

**Status:** done (2026-09-01). Example lobby + in-session AV keys on `main`.

- [x] Lobby subsection visible before Join
- [x] Enter lobby calls `start(purpose: lobby)` and does not attach Echo Transport
- [x] Join copies picks, stops lobby, starts meeting, attaches Echo Transport
- [x] In-session controls match the host narrative table
- [x] Orchestration keys exist for lobby-enter, device picks, lobby-join, mutes, camera-off
