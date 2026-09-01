# 06 — Android camera graph

**What to build:** On Android, the host can enumerate cameras, grant permission through `startPreview` / `start()`, see a Preview Texture, switch cameras, Mute-video, Camera-off, and enable video on an existing audio Session without replacing audio streams.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** done (2026-09-01). SM A176U1 Orchestration receipt.

- [x] Catalog includes facing metadata
- [x] Permission denial is a typed Start result
- [x] Preview Texture is the Production video path
- [x] Camera-off stops hardware capture
- [x] Physical-device receipt or documented equivalent for the example harness
