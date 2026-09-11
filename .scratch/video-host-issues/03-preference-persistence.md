# 03 — Host preference persistence

**What to build:** Host-persisted ordered audio Endpoint preference and
Camera preference, bound at preview and at `start()`. Mid-session picks do
not write preference.

**Blocked by:** 02 — Audio manager and catalogs

**Status:** done (2026-09-11). Tracked in GitHub issue #65; shipped in PR #67.

- [ ] Uses existing example storage if present, not a new stack
- [ ] Camera preference is a separate list from audio
- [ ] Ephemeral select is tested
- [ ] Unplug fallback walks the stored Camera preference
