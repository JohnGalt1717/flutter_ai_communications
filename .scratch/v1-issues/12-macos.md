# Desktop: macOS adapter

## Parent

See the v1 spec issue.

## What to build

macOS platform package and adapter with the same Audio manager contract: enumeration, pairing, comms channel, formats, floor, barge-in, mute/pause, SignalR-transparent reset. Highest desktop priority after v1 mobile/web.

## Acceptance criteria

- [ ] Federated macOS package is wired in the workspace
- [ ] Catalog, start permission, capture/play, mute silence, and reset-without-stream-end work
- [ ] Example runs on macOS

## Blocked by

The v1 example / Marionette ticket (mobile+web must be done first).
