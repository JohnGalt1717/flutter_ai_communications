# Example AI-voice harness with Marionette

## Parent

See the v1 spec issue.

## What to build

Example app that looks like an AI voice client: Endpoint picker (including handset/speakerphone), start / mute / pause, Isolation event surface for the host to show a prompt, Coverage indicator, visualizer on the capture stream, fixture loopback. Marionette can drive start → speak fixture → barge-in → mute → device switch to success. No SignalR.

## Acceptance criteria

- [ ] Example depends only on the app package
- [ ] Marionette (or integration_test) covers start, mute, pause, and an Isolation event
- [ ] Visualizer uses the capture stream
- [ ] Looks like an AI voice product, not a debug dump

## Blocked by

iOS, Android, and Web adapter tickets.
