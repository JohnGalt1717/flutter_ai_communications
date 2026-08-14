# OpenAI and Grok Formats with transcode

## Parent

See the v1 spec issue.

## What to build

Shared transcode so capture out and playback in can each be any OpenAI + Grok Format: PCM16 LE mono at 8 / 16 / 22.05 / 24 / 32 / 44.1 / 48 kHz, G.711 µ-law / A-law, and Opus 24 kHz mono packets. Default both edges: PCM16 LE mono 24 kHz. Internal graph stays PCM16 mono at a working rate.

## Acceptance criteria

- [ ] Fixture PCM converts to each supported Format and back with documented loss for G.711 / resample
- [ ] Capture and playback Formats may differ on one Session
- [ ] Omitted Formats default to PCM16 LE mono 24 kHz
- [ ] Tests do not depend on a real device

## Blocked by

The workspace / federated-package ticket.
