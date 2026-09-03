# 05 — macOS screen graph

**What to build:** On macOS, ScreenCaptureKit enumerates displays and
windows, Screen pick yields thumbs, indicate draws a Share frame, and
`SCStream` is the Production video path. System audio uses
`capturesAudio`. Host picker, not `SCContentSharingPicker`, is v1.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** not started

- [ ] Catalog from `SCShareableContent`; All-displays synthesized
- [ ] Screen Recording TCC at beginScreenPick or startScreenShare
- [ ] Thumbs during Screen pick; Share frame overlay
- [ ] Production `SCStream`; exclude own application from display capture
- [ ] `capturesAudio` + `excludesCurrentProcessAudio` for Include sound
- [ ] Physical receipt: TCC prompt, thumbs, Share frame, camera+screen,
      Include sound, stop
