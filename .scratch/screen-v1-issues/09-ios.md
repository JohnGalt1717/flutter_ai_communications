# 09 — iOS ReplayKit / Broadcast

**What to build:** iOS catalog is one system-picker source. Full-device
share uses ReplayKit Broadcast upload extension (or current
ScreenCaptureKit picker). In-app ReplayKit is not full-device share.
Thumbs and Share frame are no-ops.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** not started

- [ ] Catalog is one system-picker source
- [ ] startScreenShare presents Start Broadcast / SCK picker
- [ ] Broadcast extension + App Group delivers frames to the Production
      path Video surface
- [ ] App audio from ReplayKit when includeSystemAudio is on
- [ ] User stop from Control Center is source-gone, not Session stop
- [ ] Physical or sim receipt: picker → send → stop; camera+screen
