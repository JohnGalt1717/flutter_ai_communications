# 04 — Windows screen graph

**What to build:** On Windows, the host can enumerate displays, windows,
and All-displays, show Screen previews without a yellow WGC border on
every window, indicate a Share frame, and send a native Production video
path (WGC) with optional WASAPI loopback.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** in progress. GDI thumbs + Share frame shipped in #39.
WGC production + WASAPI FFI loopback in this slice.

- [x] Catalog from monitors + top-level windows; All-displays synthesized
- [x] Screen previews via GDI (not WGC; no yellow border on every window)
- [x] Share frame overlay; excluded from BitBlt / WDA_EXCLUDEFROMCAPTURE
- [x] Production: WGC CreateForMonitor / CreateForWindow (GDI fallback)
- [x] Exclude host Flutter windows from display / All-displays capture
- [x] Cursor default on (WGC `IsCursorCaptureEnabled`; GDI DrawIconEx fallback)
- [x] WASAPI loopback for includeSystemAudio (Dart FFI, not the mic Capture stream)
- [x] Automated receipt: JamieDesktop `native_screen_test` `skipped=false`
      (20 cycles, camera+screen, 1920×1080@5)
- [ ] Physical note: picker thumbs without yellow WGC borders (GDI path;
      still record on #44)
