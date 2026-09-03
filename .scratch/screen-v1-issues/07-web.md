# 07 — Web getDisplayMedia

**What to build:** Web catalog is one system-picker Screen source.
`startScreenShare` calls `getDisplayMedia`. No library thumbs or Share
frame. Tab surfaces are windows. System audio is a constraint hint;
the browser sheet is authoritative.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** in progress (PR #39). Graph shipped. Chrome receipt on #44.

- [x] `screenSources()` returns one system-picker source
- [x] beginScreenPick / indicate are no-ops
- [x] startScreenShare presents the browser picker; local Video surface
      is an HtmlElementView / view id
- [x] includeSystemAudio maps to `audio` on getDisplayMedia; live toggle
      re-enables tracks
- [x] Browser stop (`ended`) is source-gone, not Session stop
- [ ] Receipt: Chrome/Edge picker → surface → stop (#44)
