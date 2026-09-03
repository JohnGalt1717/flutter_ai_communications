# 08 — Android MediaProjection

**What to build:** Android catalog is one system-picker source.
`startScreenShare` presents the MediaProjection consent (entire screen
or one app on 14+). Foreground service type `mediaProjection` is
required. AudioPlaybackCapture for Include sound.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** in progress (PR #39). MediaProjection + FGS shipped.
AudioPlaybackCapture and SM receipt later.

- [x] Catalog is one system-picker source
- [x] Consent every start (MediaProjection intent)
- [x] Production VirtualDisplay → Texture
- [ ] AudioPlaybackCapture when includeSystemAudio is on
- [x] User stop from the system UI is source-gone (`MediaProjection.Callback`)
- [ ] Physical receipt: SM-class device, consent sheet, send, stop (#44)
