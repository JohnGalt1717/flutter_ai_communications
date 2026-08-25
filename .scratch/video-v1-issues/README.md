# Video v1 tickets

Local tracker for `docs/spec-video-v1.md`. Numbered in dependency order. Work the frontier: any ticket whose blockers are done. Do not open GitHub issues for this slice unless a human asks.

Host (Fulcrum Apps) tickets live in
`ProjectFulcrum/Apps/.scratch/video-host-issues/` and the host plan
`ProjectFulcrum/Apps/.agents/plans/2026-08-25-communications-video-host-integration.md`.

| # | Title | Blocked by |
| --- | --- | --- |
| 00 | Video spec, glossary, and ADRs | — |
| 01 | Shared video types | 00 |
| 02 | Session and platform-interface video contracts | 01 |
| 03 | Pre-join preview on the idle manager | 02 |
| 04 | Video sink provider seam | 02 |
| 05 | iOS camera graph | 02 |
| 06 | Android camera graph | 02 |
| 07 | macOS camera graph | 02 |
| 08 | Windows camera graph | 02 |
| 09 | Web camera graph | 02 |
| 10 | Video processors on iOS and Android | 03, 05, 06 |
| 11 | Video processors on macOS, Windows, and Web | 07, 08, 09, 10 |
| 12 | flutter_webrtc sink package | 04 and one native graph |
| 13 | Example landing page and in-session AV harness | 03 and one native graph |
| 14 | Host guide accuracy pass | 13 |

Plan: `.agents/plans/video-capture-and-sinks.md`.
