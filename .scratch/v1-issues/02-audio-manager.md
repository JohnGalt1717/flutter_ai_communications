# Audio manager and Session with fake platform

## Parent

See the v1 spec issue.

## What to build

A host can construct an Audio manager, read the Endpoint catalog while idle, and call `start()` against a fake platform adapter. `start()` returns a typed Start result (`ready` / `denied` / `restricted` / `unavailable` / `alreadyActive` / `failed`). A ready Session exposes one capture stream, play, mute (silence frames), pause/resume, stop, ephemeral select/setSoundFloor, Isolation and Coverage streams, and `package:logging`. A second `start()` is `alreadyActive`. Preference is accepted only as a `start()` argument.

## Acceptance criteria

- [ ] Fake-adapter tests cover every Start result
- [ ] One live Session per manager
- [ ] Mid-session Endpoint / floor picks do not change the start preference
- [ ] Mute still emits silence frames on the same capture subscription
- [ ] Pause then resume does not replace the Session or its streams
- [ ] No ISpect, no user-facing strings

## Blocked by

The workspace / federated-package ticket.
