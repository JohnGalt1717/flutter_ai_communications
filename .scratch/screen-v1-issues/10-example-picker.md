# 10 — Example in-session picker

**What to build:** `example/` meeting UI has a Share control that builds
a Teams-style picker from Screen previews on enumerable platforms, and
a Share button that calls `startScreenShare` on OS-picker platforms.

**Blocked by:** 03 — Fake Screen pick, indicate, catalog stream; and one
native graph (04–09)

**Status:** done (2026-09-03). Example Screen send subsection + loopback.

- [x] Share is in-session only; lobby shows names at most
- [x] Source list with indicate; Share starts send (OS-picker uses the single source)
- [x] Include sound, Screen motion, cursor controls
- [x] Stop share; camera tile remains; send surface loopbacks beside self-view
- [x] Keys: `screen-session`, `screen-share`, `screen-stop`, `screen-loopback`,
      `screen-source-*`
- [x] Follows `docs/host-screen-share-narrative.md`
