# 09 — iOS ReplayKit / Broadcast

**What to build:** iOS catalog is one system-picker source. Full-device
share uses ReplayKit Broadcast upload extension (or current
ScreenCaptureKit picker). In-app ReplayKit is not full-device share.
Thumbs and Share frame are no-ops.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** graph on `feat/apple-screen-send-43` — GitHub [#43](https://github.com/JohnGalt1717/flutter_ai_communications/issues/43)

- [x] Catalog is one system-picker source
- [x] startScreenShare presents Start Broadcast (`RPSystemBroadcastPickerView`)
- [x] Broadcast extension + App Group delivers frames to the Production
      path Video surface (example host `BroadcastUpload`)
- [ ] App audio from ReplayKit when includeSystemAudio is on (video-only
      in v1; Include sound is a status warning)
- [x] User stop from Control Center is source-gone, not Session stop
- [ ] Physical receipt: picker → send → stop; camera+screen. Simulator
      and wireless iPhone are not Broadcast proof.
