# 09 — Web camera graph

**What to build:** On web, `startPreview` and `start()` wait on getUserMedia, labels exist before the catalog is used, a preview surface shows the Production video path, and documented limits (facing detail, processor availability) are not treated as adapter bugs.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** done (2026-09-01). Lobby driven via flutter-skill + Agent Lens.

- [x] Permission prompt is inside start/preview and blocks
- [x] devicechange updates the camera catalog
- [x] Mute-video and Camera-off are distinct
- [x] Limits are documented for hosts
