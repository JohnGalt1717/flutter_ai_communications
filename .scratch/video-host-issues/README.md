# Video host tickets

Local tracker for
`.agents/plans/2026-08-25-communications-video-host-integration.md`.

First host surface is `example/`.

Numbered in dependency order. Work the frontier: any ticket whose blockers
are done. Do not create GitHub issues for these until a human asks.

Library tickets stay in `.scratch/video-v1-issues/`.

Status as of 2026-09-03, HEAD `4f38598`. First host surface is `example/`.
Library 04 and 12 are on `main`.

| # | Title | Blocked by | Status |
| --- | --- | --- | --- |
| 00 | Domain lock and first host surface | — | done |
| 01 | Package wiring in example | 00 | done |
| 02 | Audio manager and catalogs in example | 01 and library 01–02 | done |
| 03 | Host preference persistence | 02 | not started (`example/` does not persist Endpoint or Camera preference) |
| 04 | Unbranded Preview Texture primitive | 02 and library 03 | done (`self-view` Texture in example) |
| 05 | Example lobby subsection | 03, 04 | done (lobby shipped; persistence ticket 03 still open) |
| 06 | Join and enable-video-later | 05 and library 02 | done |
| 07 | In-session AV controls | 06 | done |
| 08 | Host Transport and flutter_webrtc sink | 07 and library 04, 12 | partial — `WebrtcVideoSink` attaches on Join; Echo is audio; RTCVideoView loopback remaining |
| 09 | Orchestration path and receipts | 07 and one native library graph | in progress (keys exist; Linux camera receipt remaining) |
| 10 | Docs pass | 09 | in progress (plan status updated 2026-09-01) |
