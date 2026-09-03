# Screen send v1 tickets

Local tracker for `docs/spec-screen-v1.md`. Numbered in dependency order.
Work the frontier: any ticket whose blockers are done. Apple native graphs
are tracked as GitHub issue #43.

Plan: `.agents/plans/screen-capture-and-send.md`.
Host narrative: `docs/host-screen-share-narrative.md`.
Camera tickets stay in `.scratch/video-v1-issues/`.

Status as of 2026-09-03.

| # | Title | Blocked by | Status |
| --- | --- | --- | --- |
| 00 | Spec, glossary, and ADRs | — | done |
| 01 | Shared screen types | 00 | done |
| 02 | Session and platform-interface screen contracts | 01 | done |
| 03 | Fake Screen pick, indicate, catalog stream | 02 | done |
| 04 | Windows screen graph | 02 | in progress (GDI capture + Share frame; WASAPI loopback later) |
| 05 | macOS screen graph | 02 | not started ([#43](https://github.com/JohnGalt1717/flutter_ai_communications/issues/43)) |
| 06 | Linux screen graph (X11 + Wayland) | 02 | in progress (X11 capture; Wayland system-picker) |
| 07 | Web getDisplayMedia | 02 | in progress |
| 08 | Android MediaProjection | 02 | in progress |
| 09 | iOS ReplayKit / Broadcast | 02 | not started ([#43](https://github.com/JohnGalt1717/flutter_ai_communications/issues/43)) |
| 10 | Example in-session picker | 03 and one native graph | done |
| 11 | Host narrative + Orchestration keys | 10 | in progress ([#44](https://github.com/JohnGalt1717/flutter_ai_communications/issues/44)) |
| 12 | Transport second send path | 02 | not started |
