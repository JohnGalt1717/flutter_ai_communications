# 11 — Host narrative + Orchestration keys

**What to build:** Keep the host narrative accurate and drive join → pick
→ share → stop on a real head. Physical receipts per platform as the
graphs land.

**Blocked by:** 10 — Example in-session picker

**Status:** in progress — GitHub [#44](https://github.com/JohnGalt1717/flutter_ai_communications/issues/44)

- [x] `docs/host-screen-share-narrative.md` matches the example
- [x] Orchestration keys exist and do not collide with lobby keys
- [x] Automated suite: `example/integration_test/native_screen_test.dart`
- [x] Agent job: `.agents/workflows/screen-send-orchestration.md`
- [x] Windows automated receipt: JamieDesktop `native_screen_test`
      `skipped=false` (20 cycles, camera+screen)
- [ ] Linux X11 / Wayland, Chrome, Android, macOS, iOS receipts on #44
- [ ] Windows flutter-skill note: picker thumbs without yellow WGC
      borders (GDI path; still record on #44)
