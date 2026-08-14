# Local barge-in with preroll

## Parent

See the v1 spec issue.

## What to build

Local barge-in: voice-band detector flushes playback immediately and keeps ~200–300 ms of capture preroll so the first word is on the capture stream. Host may set `BargeInPolicy.remoteVad` to skip local flush. Mute still sends silence; pause stops both sides.

## Acceptance criteria

- [ ] Fixture barge-in during playback flushes play and includes preroll on capture
- [ ] `remoteVad` does not flush
- [ ] First-word fixture is not clipped by the floor after playback starts
- [ ] Tests use fixture PCM

## Blocked by

The Audio manager + fake platform ticket.
