# flutter_ai_communications_linux

Best-effort Linux adapter. Same Audio manager contract as the other
federated packages.

## How it talks to the OS

Dart FFI against the PulseAudio compatibility libraries:

- `libpulse.so.0` — catalog (sources / sinks) and device metadata
- `libpulse-simple.so.0` — capture and playback of PCM16 LE mono 24 kHz

PipeWire hosts work through `pipewire-pulse`. There is no separate
PipeWire native graph in v1.

## Permission

There is no first-party microphone sheet on stock Linux. `start()`
probes Pulse / PipeWire: granted if a capture stream opens, otherwise
denied. Sandboxed hosts (Flatpak / Snap) must grant the Pulse or
PipeWire socket themselves. WSL / WSLg capture is the Windows
microphone forwarded as `RDPSource` — allow desktop apps under
Windows Settings → Privacy → Microphone.

Bluetooth identity is best-effort and must not block audio. BlueZ
`busctl` lists remembered/connected devices with no extra prompt.
Denial or a missing `bluetoothd` leaves Pulse names and the
known-profile registry falls back to those names.

## Bluetooth identity

Pulse `device.bus` / `device.form_factor` set Route class (including
`form_factor=car`). BlueZ Alias, Address, Class of Device, and
ManufacturerData company identifiers enrich matching Endpoints:
advertised name plus brand tokens (Sony, Apple, …) for Acoustic-profile
matching, and Class of Device for headset / speaker / car form factor.
Pulse `bluez_sink.aa_bb_….a2dp_sink` ids match BlueZ addresses that use
colons or underscores.

## Gaps versus iOS / Android

These are documented limits, not bugs:

- **No Isolation.** Events are always `unavailable`.
  `openIsolationSettings()` is a no-op.
- **No handset Endpoint.** Built-in speakers and mics are
  `speakerphone`. Bluetooth / USB are `bluetooth` / `wired`.
- **No OS microphone prompt.** Permission is “can we open a capture
  stream?” — granted if Pulse/PipeWire allows it, otherwise denied.
  There is no extra Bluetooth prompt. Pulse `form_factor=car` is a
  car Route class; otherwise Tesla and other head-unit names match
  the known-profile registry.
- **AEC / NS / AGC** are whatever the server already applies. This
  adapter does not configure a communications module.
- **Quality is best-effort.** Capture uses a blocking simple stream on
  an isolate. Endpoint switches restart the graph and emit a silence
  frame so the Session capture subscription survives (ADR-0004).
- **WSLg** exposes the Windows default route as `RDPSource` /
  `RDPSink`, not per-device Bluetooth Endpoints from the Windows
  radio. Native Linux Bluetooth needs BlueZ on the Linux host.
