# Android adapter: enum, speakerphone, transparent reset

## Parent

See the v1 spec issue.

## What to build

Android adapter: enumeration with metadata, handset and speakerphone Endpoints, `MODE_IN_COMMUNICATION`, AEC/NS/AGC, permission inside `start()`, OEM-safe route switches, and SignalR-transparent reset. Pixel and high-end Samsung should be excellent; cheaper OEMs must still enumerate and not crash. No Isolation API.

## Acceptance criteria

- [ ] Catalog includes handset and speakerphone
- [ ] `start()` blocks on `RECORD_AUDIO` and can return `denied`
- [ ] Speakerphone vs handset actually changes the OS route
- [ ] Capture subscriptions survive a route change
- [ ] Isolation reports `unavailable` (not a start failure)

## Blocked by

Audio manager, pairing, and formats tickets.
