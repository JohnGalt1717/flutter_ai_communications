# Video host tickets

Local tracker for
`.agents/plans/2026-08-25-communications-video-host-integration.md`.

First host surface is `example/`.

Numbered in dependency order. Work the frontier: any ticket whose blockers
are done. Do not create GitHub issues for these until a human asks.

Library tickets stay in `.scratch/video-v1-issues/`.

| # | Title | Blocked by |
| --- | --- | --- |
| 00 | Domain lock and first host surface | — |
| 01 | Package wiring in example | 00 |
| 02 | Audio manager and catalogs in example | 01 and library 01–02 |
| 03 | Host preference persistence | 02 |
| 04 | Unbranded Preview Texture primitive | 02 and library 03 |
| 05 | Example landing page | 03, 04 |
| 06 | Join, promote, enable-video-later | 05 and library 02 |
| 07 | In-session AV controls | 06 |
| 08 | Host Transport and flutter_webrtc sink | 07 and library 04, 12 |
| 09 | Marionette path and receipts | 07 and one native library graph |
| 10 | Docs pass | 09 |
