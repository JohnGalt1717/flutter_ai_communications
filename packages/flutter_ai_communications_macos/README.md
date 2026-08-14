# flutter_ai_communications_macos

macOS adapter. Same Audio manager contract as the other federated
packages.

## How it talks to the OS

Dart FFI against Core Audio / AudioToolbox:

- `AudioObjectGetPropertyData` — catalog (devices, UID, transport)
- `AudioQueue` — capture and playback of PCM16 LE mono 24 kHz

There is no Swift MethodChannel plugin. The host app still owns
`NSMicrophoneUsageDescription` and the `audio-input` entitlement.

## Gaps versus iOS / Android

These are documented limits, not bugs:

- **No Isolation.** Events are always `unavailable`.
  `openIsolationSettings()` is a no-op.
- **No handset Endpoint.** Built-in speakers and mics are
  `speakerphone`. Bluetooth / USB are `bluetooth` / `wired`.
- **Permission** is “can we open a capture queue?” TCC may still
  prompt the first time `start()` runs.
- **AEC / NS / AGC** are whatever Core Audio already applies.
- **Quality is best-effort.** Endpoint switches restart the graph
  and emit a silence frame so the Session capture subscription
  survives (ADR-0004).
