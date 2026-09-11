# 11 — Video processors on macOS, Windows, and Web

**What to build:** Desktop and web hosts get the same Video processor API. Where on-device segmentation is weak, the adapter documents the gap, falls back to none, and still keeps preview and sinks on one path.

**Blocked by:** 07 — macOS camera graph; 08 — Windows camera graph; 09 — Web camera graph; 10 — Video processors on iOS and Android

**Status:** done (2026-09-11). Tracked in GitHub issue #63; shipped in PRs #68, #70, #71, #73.

- [ ] Same public processor types as mobile
- [ ] Fallback is a warning, not a crash
- [ ] Documented per-platform processor support matrix
