# 03 — Host preference persistence

**What to build:** Host-persisted ordered audio Endpoint preference and
Camera preference, bound at preview and at `start()`. Mid-session picks do
not write preference.

**Blocked by:** 02 — Audio manager and catalogs

**Status:** not started (2026-09-01). `example/lib/main.dart` does not persist Endpoint preference or Camera preference.

- [ ] Uses existing example storage if present, not a new stack
- [ ] Camera preference is a separate list from audio
- [ ] Ephemeral select is tested
- [ ] Unplug fallback walks the stored Camera preference
