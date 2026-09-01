# 01 — Package wiring in example

**What to build:** `example/` depends on the workspace library packages.
No native camera code is copied into the example.

**Blocked by:** 00 — Domain lock and first host surface

**Status:** done (2026-09-01). Example depends on workspace packages; camera graphs stay in federated packages.

- [ ] Workspace path deps cover communications + webrtc sink when it exists
- [ ] Analyzer is clean on touched pubspecs
- [ ] A unit test can import library types
- [ ] No `camera` plugin added as a preview shortcut
