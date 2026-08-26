# flutter_ai_communications_windows

Windows adapter. Same Audio manager contract as the other federated
packages.

## How it talks to the OS

Dart FFI against WASAPI via `package:win32`:

- `IMMDeviceEnumerator` — catalog (capture / render Endpoints)
- Shared-mode `IAudioClient` with `AUTOCONVERTPCM` — PCM16 LE mono 24 kHz

## Gaps versus iOS / Android

These are documented limits, not bugs:

- **No Isolation.** Events are always `unavailable`.
  `openIsolationSettings()` is a no-op.
- **No handset Endpoint.** Built-in speakers and mics are
  `speakerphone`. Bluetooth / USB are `bluetooth` / `wired`.
- **No OS microphone prompt from this package.** Permission is
  “can we open a capture client?” — granted if WASAPI allows it.
  The host must keep Windows Settings → Privacy → Microphone →
  “Let desktop apps access your microphone” allowed.
- **AEC / NS / AGC** are whatever the communications Endpoint
  already applies. The graph asks WASAPI for the communications
  stream category; it does not configure a vendor APO.
- **Quality is best-effort.** Endpoint switches restart the graph
  and emit a silence frame so the Session capture subscription
  survives (ADR-0004).
