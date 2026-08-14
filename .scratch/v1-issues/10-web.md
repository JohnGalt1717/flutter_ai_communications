# Web adapter: getUserMedia, pairing, documented limits

## Parent

See the v1 spec issue.

## What to build

Web adapter: `start()` blocks on `getUserMedia`, then `enumerateDevices` + `groupId` pairing, echoCancellation / noiseSuppression / autoGainControl constraints, adaptive floor, barge-in, mute-silence. No Isolation, no handset. Blank labels before permission are not a catalog the host should see after `ready`. Documented limits, not bugs.

## Acceptance criteria

- [ ] Denied permission returns `denied` and does not start a Session
- [ ] After `ready`, Endpoints have usable labels when the browser provides them
- [ ] Pairing uses `groupId`
- [ ] Isolation is `unavailable`; there is no handset Endpoint
- [ ] Capture stream is the same bytes a visualizer would plot

## Blocked by

Audio manager, pairing, formats, floor, and barge-in tickets.
