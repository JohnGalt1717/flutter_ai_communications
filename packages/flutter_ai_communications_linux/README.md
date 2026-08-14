# flutter_ai_communications_linux

Best-effort Linux adapter. Same Audio manager contract as the other
federated packages.

## How it talks to the OS

Dart FFI against the PulseAudio compatibility libraries:

- `libpulse.so.0` — catalog (sources / sinks) and device metadata
- `libpulse-simple.so.0` — capture and playback of PCM16 LE mono 24 kHz

PipeWire hosts work through `pipewire-pulse`. There is no separate
PipeWire native graph in v1.

## Gaps versus iOS / Android

These are documented limits, not bugs:

- **No Isolation.** Events are always `unavailable`.
  `openIsolationSettings()` is a no-op.
- **No handset Endpoint.** Built-in speakers and mics are
  `speakerphone`. Bluetooth / USB are `bluetooth` / `wired`.
- **No OS microphone prompt.** Permission is “can we open a capture
  stream?” — granted if Pulse/PipeWire allows it, otherwise denied.
- **AEC / NS / AGC** are whatever the server already applies. This
  adapter does not configure a communications module.
- **Quality is best-effort.** Capture uses a blocking simple stream on
  an isolate. Endpoint switches restart the graph and emit a silence
  frame so the Session capture subscription survives (ADR-0004).
