# Adaptive and fixed sound floor

## Parent

See the v1 spec issue.

## What to build

Shared sound floor on the capture stream: adaptive by default (voice band vs the rest; rises on lounge / car / bad-BT), or a host-set fixed value (`null` = adaptive). Isolation / AEC / NS stay on; the floor backfills when they lie. The same capture stream is what the Transport and visualizer see.

## Acceptance criteria

- [ ] Fixture lounge + voice raises the adaptive floor and drops non-voice from capture
- [ ] A fixed floor is honored; `null` returns to adaptive
- [ ] Ephemeral `setSoundFloor` does not persist
- [ ] Tests use fixture PCM, not a live mic

## Blocked by

The Audio manager + fake platform ticket.
