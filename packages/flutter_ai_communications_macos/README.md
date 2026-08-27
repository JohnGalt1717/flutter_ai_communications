# flutter_ai_communications_macos

macOS adapter. Same Audio manager contract as the other federated
packages.

## How it talks to the OS

One native duplex `AVAudioEngine` (MethodChannel), same shape as iOS:

- Capture tap and playback player share one engine so VoiceProcessingIO
  receives the rendered reference (the Scribe split-engine leak).
- Isolation is unavailable. The Session emits `unavailable` and raises
  the Sound floor.
- The host app still owns `NSMicrophoneUsageDescription` and the
  `audio-input` entitlement. No CocoaPods podspec.

## Gaps versus iOS / Android

These are documented limits, not bugs:

- **No Isolation UI.** Events are always `unavailable`; the Session
  raises the Sound floor instead.
- **No handset Endpoint.** Built-in speakers and mics are
  `speakerphone`. Bluetooth / USB are `bluetooth` / `wired`.
- **Permission** is requested on first `start()` via AVFoundation.
  There is no extra Bluetooth prompt; transport type plus display
  name feed Acoustic-profile matching (Tesla and other car names
  included).
- **Quality is best-effort.** Endpoint switches restart the graph
  and emit a silence frame so the Session capture subscription
  survives (ADR-0004).
