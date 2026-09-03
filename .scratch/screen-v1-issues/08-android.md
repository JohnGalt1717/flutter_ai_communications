# 08 — Android MediaProjection

**What to build:** Android catalog is one system-picker source.
`startScreenShare` presents the MediaProjection consent (entire screen
or one app on 14+). Foreground service type `mediaProjection` is
required. AudioPlaybackCapture for Include sound.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** not started

- [ ] Catalog is one system-picker source
- [ ] Consent every session (token is single-use on API 34+)
- [ ] Production VirtualDisplay → Texture; FLAG_SECURE is black frames
- [ ] AudioPlaybackCapture when includeSystemAudio is on
- [ ] User stop from the status chip is source-gone, not Session stop
- [ ] Physical receipt: SM-class device, consent sheet, send, stop
