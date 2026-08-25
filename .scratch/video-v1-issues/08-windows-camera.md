# 08 — Windows camera graph

**What to build:** On Windows, the host can enumerate cameras, honor Camera preference fallback, show a Preview Texture, Mute-video, Camera-off, and enable video later on the same Session.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** ready-for-agent

- [ ] External cameras appear in the catalog
- [ ] Unplug falls back when preference controls the pick
- [ ] Explicit camera selection does not silently fall back
- [ ] Permission denial is a typed result
