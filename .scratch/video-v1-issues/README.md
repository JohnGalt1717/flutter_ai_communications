# Video v1 tickets

Local tracker for `docs/spec-video-v1.md`. Numbered in dependency order. Work the frontier: any ticket whose blockers are done. Do not open GitHub issues for this slice unless a human asks.

Host-integration tickets live in `.scratch/video-host-issues/`.
First host surface is `example/`. Remaining hardware work is tracked in
GitHub issues #26 (physical audio) and #44 (screen-send receipts).

Status as of 2026-09-11. Tickets 04 (#45 / PR #46), 10–11 (#63), 12
(#47 / PR #48) on `main`. **Open:** #26, #44.

| # | Title | Blocked by | Status |
| --- | --- | --- | --- |
| 00 | Video spec, glossary, and ADRs | — | done |
| 01 | Shared video types | 00 | done |
| 02 | Session and platform-interface video contracts | 01 | done |
| 03 | Lobby Session | 02 | done |
| 04 | Video sink provider seam | 02 | done (#45 / PR #46) |
| 05 | iOS camera graph | 02 | done (sim receipt) |
| 06 | Android camera graph | 02 | done (SM A176U1 receipt) |
| 07 | macOS camera graph | 02 | done (graph + audio Orchestration) |
| 08 | Windows camera graph | 02 | done (LifeCam Studio native_camera_test, `e6b37b4`) |
| — | Linux camera graph | 02 | graph landed for VM compile — receipts remaining |
| 09 | Web camera graph | 02 | done (lobby via flutter-skill) |
| 10 | Video processors on iOS and Android | 03, 05, 06 | done (#63) |
| 11 | Video processors on macOS, Windows, and Web | 07, 08, 09, 10 | done (#63) |
| 12 | flutter_webrtc sink package | 04 and one native graph | done (#47 / PR #48) |
| 13 | Example lobby and in-session AV harness | 03 and one native graph | done |
| 14 | Host guide accuracy pass | 13 | in progress |

Screen send tickets: `.scratch/screen-v1-issues/`.
