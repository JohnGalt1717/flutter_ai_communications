# 07 — Web getDisplayMedia

**What to build:** Web catalog is one system-picker Screen source.
`startScreenShare` calls `getDisplayMedia`. No library thumbs or Share
frame. Tab surfaces are windows. System audio is a constraint hint;
the browser sheet is authoritative.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** not started

- [ ] `screenSources()` returns one system-picker source
- [ ] beginScreenPick / indicate are no-ops
- [ ] startScreenShare presents the browser picker; local Video surface
      is an HtmlElementView / view id
- [ ] includeSystemAudio maps to `systemAudio` / tab-audio hints
- [ ] iOS Safari has no getDisplayMedia; catalog empty or share fails
      typed, Session stays up
- [ ] Receipt: Chrome/Edge picker → surface → stop
