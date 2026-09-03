# 02 — Session and platform-interface screen contracts

**What to build:** Communications manager and Session expose the public
screen API. Platform interface methods default to unimplemented. Start
failures are values. Lobby and `start()` never start screen send.

**Blocked by:** 01 — Shared screen types

**Status:** done (2026-09-03). Session API + fake in #39. Native graphs
for Windows/Linux/Android/web shipped in the same PR.

- [x] `manager.screenSources()` snapshot (idle or live)
- [x] `session.beginScreenPick` / `endScreenPick` / `indicateScreenSource`
- [x] `session.startScreenShare` / `stopScreenShare` / live toggles
- [x] `session.screenSurface`, `isScreenSending`, catalog stream
- [x] Lobby pick/share is a typed failure; Session stays up
- [x] Session settings do not include screen send
- [x] Platform methods default unimplemented so older adapters load
- [x] Permission is requested at pick or share, not Session `start()`
