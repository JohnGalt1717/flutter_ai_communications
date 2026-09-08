# Screen send v1 tickets

Local tracker for `docs/spec-screen-v1.md`. Numbered in dependency order.
Work the frontier: any ticket whose blockers are done. Apple native graphs
are tracked as GitHub issue #43.

Plan: `.agents/plans/screen-capture-and-send.md`.
Host narrative: `docs/host-screen-share-narrative.md`.
Camera tickets stay in `.scratch/video-v1-issues/`.

Status as of 2026-09-08. HEAD `5642764`. Graphs shipped. Receipts on #44.

| # | Title | Blocked by | Status |
| --- | --- | --- | --- |
| 00 | Spec, glossary, and ADRs | — | done |
| 01 | Shared screen types | 00 | done |
| 02 | Session and platform-interface screen contracts | 01 | done |
| 03 | Fake Screen pick, indicate, catalog stream | 02 | done |
| 04 | Windows screen graph | 02 | done (WGC + WASAPI FFI; `skipped=false`) |
| 05 | macOS screen graph | 02 | done (#43; `native_screen_test` `skipped=false`) |
| 06 | Linux screen graph (X11 + Wayland) | 02 | X11 graph in tree; **X11 receipt remaining on #44**. Wayland portal in tree |
| 07 | Web getDisplayMedia | 02 | done (Chrome flutter-skill `skipped=false` on #44) |
| 08 | Android MediaProjection | 02 | video `skipped=false`; AudioPlaybackCapture shipped (#51 / PR #58); **Include-sound sheet remaining on #44** |
| 09 | iOS ReplayKit / Broadcast | 02 | done (physical Broadcast `skipped=false` on #44) |
| 10 | Example in-session picker | 03 and one native graph | done |
| 11 | Host narrative + Orchestration keys | 10 | in progress ([#44](https://github.com/JohnGalt1717/flutter_ai_communications/issues/44); Linux X11 + Android Include-sound) |
| 12 | Transport second send path | 02 | not started (camera WebRTC Send track is #48; screen path still open) |
