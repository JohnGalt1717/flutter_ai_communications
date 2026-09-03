# 04 — Windows screen graph

**What to build:** On Windows, the host can enumerate displays, windows,
and All-displays, show Screen previews without a yellow WGC border on
every window, indicate a Share frame, and send a native Production video
path (WGC) with optional WASAPI loopback.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** in progress (PR #39). GDI BitBlt + Share frame + thumbs.
WGC production and WASAPI loopback later.

- [x] Catalog from monitors + top-level windows; All-displays synthesized
- [x] Screen previews via GDI (not WGC; no yellow border on every window)
- [x] Share frame overlay; excluded from BitBlt
- [ ] Production: WGC CreateForMonitor / CreateForWindow (v1 ships GDI)
- [x] Exclude host Flutter windows from display / All-displays capture
- [x] Cursor default on
- [ ] WASAPI loopback for includeSystemAudio
- [x] Automated receipt: JamieDesktop `native_screen_test` `skipped=false`
      (20 cycles, camera+screen, 1920×1080@5)
- [ ] Physical note: picker thumbs without yellow WGC borders (GDI path;
      still record on #44)
