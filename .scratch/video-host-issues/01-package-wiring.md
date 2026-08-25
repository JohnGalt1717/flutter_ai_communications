# 01 — Package wiring in example

**What to build:** `example/` depends on the workspace library packages.
No native camera code is copied into the example.

**Blocked by:** 00 — Domain lock and first host surface

**Status:** ready-for-agent

- [ ] Workspace path deps cover communications + webrtc sink when it exists
- [ ] Analyzer is clean on touched pubspecs
- [ ] A unit test can import library types
- [ ] No `camera` plugin added as a preview shortcut
