# 06 — Android camera graph

**What to build:** On Android, the host can enumerate cameras, grant permission through `startPreview` / `start()`, see a Preview Texture, switch cameras, Mute-video, Camera-off, and enable video on an existing audio Session without replacing audio streams.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** ready-for-agent

- [ ] Catalog includes facing metadata
- [ ] Permission denial is a typed Start result
- [ ] Preview Texture is the Production video path
- [ ] Camera-off stops hardware capture
- [ ] Physical-device receipt or documented equivalent for the example harness
