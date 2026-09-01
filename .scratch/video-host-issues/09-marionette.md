# 09 — Orchestration path and receipts

**What to build:** An agent can drive the **example lobby** → Join → mutes →
Camera-off → live camera flip → leave on a real head. Fake-adapter tests are
not native proof. Do not call this Marionette.

**Blocked by:** 07 — In-session controls; one library native graph (audio lobby
path can run against today’s Session)

**Status:** in progress (2026-09-01). Keys and native Orchestration suite exist. Linux camera receipt remaining. Windows LifeCam Studio camera receipt on `e6b37b4`.

- [x] Keys are stable on lobby and in-session controls
- [x] Native Orchestration suite enters a lobby Session then a meeting Session
- [ ] Flutter debug processes torn down by numeric PID
- [x] Receipt names platform and commit
