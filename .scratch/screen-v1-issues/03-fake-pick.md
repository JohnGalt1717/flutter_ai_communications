# 03 — Fake Screen pick, indicate, catalog stream

**What to build:** Fake platform adapter covers Screen pick thumbs,
indicate without send, live catalog updates, replace, source-gone, and
system-picker behavior so Session tests do not need a real display.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** done (2026-09-03). Fake adapter + `session_screen_test.dart`.

- [x] Fake catalog of display, window, All-displays, and system-picker
- [x] beginScreenPick yields Screen preview handles; endScreenPick tears
      them down
- [x] indicateScreenSource records the indicated id without starting send
- [x] startScreenShare on system-picker binds a returned display/window
- [ ] Catalog stream emits add/remove; vanished send source stops screen
      send and publishes Session status
- [ ] includeSystemAudio does not appear on the mic Capture stream
- [ ] Camera-off / Camera preview do not stop screen send
