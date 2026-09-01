# 05 — iOS camera graph

**What to build:** On iOS, the host can enumerate front and back cameras, grant camera permission through `startPreview` / `start()`, see a Preview Texture, switch cameras, Mute-video, Camera-off (lens indicator off), and enable video on an existing audio Session without replacing audio streams.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** done (2026-09-01). iPhone 17 sim Orchestration. Physical iPhone Allow-dialog receipt still open on the video plan.

- [x] Catalog includes facing metadata
- [x] Permission denial is a typed Start result
- [x] Preview Texture is the Production video path
- [x] Camera-off stops hardware capture
- [x] Physical-device receipt or documented equivalent for the example harness (sim)
