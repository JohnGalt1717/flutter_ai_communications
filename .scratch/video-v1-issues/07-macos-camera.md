# 07 — macOS camera graph

**What to build:** On macOS, the host can enumerate built-in and external cameras, honor Camera preference fallback when a USB camera unplugs, show a Preview Texture, Mute-video, Camera-off, and enable video later on the same Session.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** ready-for-agent

- [ ] External cameras appear in the catalog
- [ ] Unplug falls back when preference controls the pick
- [ ] Explicit camera selection does not silently fall back
- [ ] Entitlement / permission denial is a typed result
