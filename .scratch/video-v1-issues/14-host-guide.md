# 14 — Host guide accuracy pass

**What to build:** `docs/host-prejoin-narrative.md` matches the shipped APIs so a host can build Teams-like or Zoom-like chrome without reading source. Gaps against those products are listed as follow-up tickets, not left implicit.

**Blocked by:** 13 — Example landing page and in-session AV harness

**Status:** in progress (2026-09-03). `docs/host-prejoin-narrative.md` matches
lobby Session + Join. WebRTC attach is in `docs/host-webrtc-narrative.md`.
Remaining: any missing Teams/Zoom control filed as follow-up.

- [x] Narrative call names match the public API
- [x] Failure mapping matches Start results
- [x] WebRTC Send-track attach documented
- [ ] Any missing Teams/Zoom control is filed, not papered over
