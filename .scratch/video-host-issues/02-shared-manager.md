# 02 — Audio manager and catalogs in example

**What to build:** One application-scoped Audio manager in the example. Idle
audio and camera catalogs are available to view models. Expected permission
and already-active failures are values, not thrown exceptions.

**Blocked by:** 01 — Package wiring; library tickets 01–02

**Status:** done (2026-09-01). Example uses one `CommunicationsManager` and idle `endpoints()` / `cameras()`.

- [ ] One manager per app process
- [ ] `endpoints()` and `cameras()` work while idle
- [ ] Session purpose is set so already-active names the owner
- [ ] Fake-backed tests cover catalogs and already-active
- [ ] No product strings in library packages
