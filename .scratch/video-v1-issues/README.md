# Video v1 tickets

Local tracker for `docs/spec-video-v1.md`. Numbered in dependency order. Work the frontier: any ticket whose blockers are done. Do not open GitHub issues for this slice unless a human asks.

Host-integration tickets live in `.scratch/video-host-issues/` and the host plan
`.agents/plans/2026-08-25-communications-video-host-integration.md`.
Both are in this repository. First host surface is `example/`.

Status as of 2026-09-03. Ticket 04 Video sink seam on `feat/04-video-sink-seam` (#45).

| # | Title | Blocked by | Status |
| --- | --- | --- | --- |
| 00 | Video spec, glossary, and ADRs | — | done |
| 01 | Shared video types | 00 | done |
| 02 | Session and platform-interface video contracts | 01 | done |
| 03 | Lobby Session | 02 | done |
| 04 | Video sink provider seam | 02 | done (#45) |
| 05 | iOS camera graph | 02 | done (sim receipt) |
| 06 | Android camera graph | 02 | done (SM A176U1 receipt) |
| 07 | macOS camera graph | 02 | done (graph + audio Orchestration) |
| 08 | Windows camera graph | 02 | done (LifeCam Studio native_camera_test, `e6b37b4`) |
| — | Linux camera graph | 02 | graph landed for VM compile — receipts remaining |
| 09 | Web camera graph | 02 | done (lobby via flutter-skill) |
| 10 | Video processors on iOS and Android | 03, 05, 06 | deferred |
| 11 | Video processors on macOS, Windows, and Web | 07, 08, 09, 10 | deferred |
| 12 | flutter_webrtc sink package | 04 and one native graph | not started |
| 13 | Example lobby and in-session AV harness | 03 and one native graph | done |
| 14 | Host guide accuracy pass | 13 | in progress |

Plan: `.agents/plans/video-capture-and-sinks.md`.
Screen send tickets: `.scratch/screen-v1-issues/`.
