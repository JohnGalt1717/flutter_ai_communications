# 04 — Windows screen graph

**What to build:** On Windows, the host can enumerate displays, windows,
and All-displays, show Screen previews without a yellow WGC border on
every window, indicate a Share frame, and send a native Production video
path (WGC) with optional WASAPI loopback.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** not started

- [ ] Catalog from monitors + top-level windows; All-displays synthesized
- [ ] Screen previews via DWM/PrintWindow, not WGC
- [ ] Share frame overlay; suppress OS capture border where allowed
- [ ] Production: WGC CreateForMonitor / CreateForWindow; stitch
      All-displays
- [ ] Exclude host Flutter windows from display / All-displays capture
- [ ] Cursor default on; WASAPI loopback for includeSystemAudio
- [ ] Physical receipt: thumbs without yellow borders, Share frame,
      camera+screen together, stop, cycles without leaking capture
