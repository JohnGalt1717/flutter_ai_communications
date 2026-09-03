# 05 — macOS screen graph

**What to build:** On macOS, ScreenCaptureKit enumerates displays and
windows, Screen pick yields thumbs, indicate draws a Share frame, and
`SCStream` is the Production video path. System audio uses
`capturesAudio`. Host picker, not `SCContentSharingPicker`, is v1.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** done on `feat/apple-screen-send-43` — GitHub [#43](https://github.com/JohnGalt1717/flutter_ai_communications/issues/43)

- [x] Catalog from `SCShareableContent`; All-displays synthesized
- [x] Screen Recording TCC at beginScreenPick or startScreenShare
- [x] Thumbs during Screen pick; Share frame overlay
- [x] Production `SCStream`; exclude own application from display capture
- [x] `capturesAudio` + `excludesCurrentProcessAudio` for Include sound
- [x] Physical receipt: `native_screen_test` vs `macos`, `skipped=false`,
      20 cycles, camera+screen, Include sound applied
