# iOS adapter: enum, Isolation, transparent reset

## Parent

See the v1 spec issue.

## What to build

iOS adapter: full Endpoint enumeration with metadata, handset and speakerphone as distinct Endpoints, communications-channel init, AEC/NS/AGC, Isolation detect + open system microphone-mode UI via an internal hold, permission request inside `start()`, and SignalR-transparent reset (same Session streams; silence during teardown; in-place switch only if proven). Isolation events only — no dialog strings.

## Acceptance criteria

- [ ] Catalog includes handset and speakerphone
- [ ] `start()` blocks on mic permission and can return `denied`
- [ ] Isolation off emits an event and still returns `ready`; `openIsolationSettings()` can be called
- [ ] Endpoint change does not end existing capture subscriptions
- [ ] Pair follow works for a Bluetooth headset when the OS reports it

## Blocked by

Audio manager, pairing, and formats tickets.
