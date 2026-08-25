# 05 — iOS camera graph

**What to build:** On iOS, the host can enumerate front and back cameras, grant camera permission through `startPreview` / `start()`, see a Preview Texture, switch cameras, Mute-video, Camera-off (lens indicator off), and enable video on an existing audio Session without replacing audio streams.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** ready-for-agent

- [ ] Catalog includes facing metadata
- [ ] Permission denial is a typed Start result
- [ ] Preview Texture is the Production video path
- [ ] Camera-off stops hardware capture
- [ ] Physical-device receipt or documented equivalent for the example harness
