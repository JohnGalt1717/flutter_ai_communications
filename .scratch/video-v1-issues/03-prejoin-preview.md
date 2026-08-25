# 03 — Pre-join preview on the idle manager

**What to build:** A host can start and stop Pre-join preview without creating a Session, show a Preview Texture, apply a Video processor, switch cameras, and Camera-off in the lobby. `start()` can promote or override that camera and processor. Preview does not occupy the one-Session slot and does not emit Transport silence frames.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** ready-for-agent

- [ ] Preview works while no Session exists
- [ ] Starting a Session stops or promotes preview; a second Session is still alreadyActive
- [ ] Processor selected on preview is visible on the Preview Texture in the fake adapter
- [ ] Leaving the lobby (`preview.stop`) does not require `session.stop`
