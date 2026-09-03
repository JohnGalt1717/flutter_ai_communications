# 10 — Example in-session picker

**What to build:** `example/` meeting UI has a Share control that builds
a Teams-style picker from Screen previews on enumerable platforms, and
a Share button that calls `startScreenShare` on OS-picker platforms.

**Blocked by:** 03 — Fake Screen pick, indicate, catalog stream; and one
native graph (04–09)

**Status:** not started

- [ ] Share is in-session only; lobby shows names at most
- [ ] Grid of Screen previews; click indicates; confirm starts send
- [ ] Include sound, Screen motion, cursor controls
- [ ] Stop share; camera tile remains
- [ ] Keys for Orchestration: open picker, indicate, share, stop
- [ ] Follows `docs/host-screen-share-narrative.md`
