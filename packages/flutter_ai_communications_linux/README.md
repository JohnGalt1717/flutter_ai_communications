# flutter_ai_communications_linux

Best-effort Linux adapter. Same Audio manager contract as the other
federated packages.

## How it talks to the OS

Dart FFI against the PulseAudio compatibility libraries:

- `libpulse.so.0` — catalog (sources / sinks) and device metadata
- `libpulse-simple.so.0` — capture and playback of PCM16 LE mono 24 kHz

Native Format is always PCM16 LE mono 24 kHz (ADR-0008). Requested
16 kHz does not change the graph. `noiseCancelling` runs Speex AEC/NS/AGC
on capture (playback as reverse). Missing `libspeexdsp.so.1` is
pass-through. Neither case fails `start()`. Failed start emits
`CoverageHint.dead`.

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
- **AEC / NS / AGC** run in-process via Speex when `noiseCancelling`
  is on. Isolation is still always `unavailable`.
- **Quality is best-effort.** Capture uses a blocking simple stream on
  an isolate. Endpoint switches restart the graph and emit a silence
  frame so the Session capture subscription survives (ADR-0004).
- **WSLg** exposes the Windows default route as `RDPSource` /
  `RDPSink`, not per-device Bluetooth Endpoints from the Windows
  radio. Native Linux Bluetooth needs BlueZ on the Linux host.

## Camera

V4L2 (`/dev/video*`) feeds a Flutter Texture. Catalog modes come from
`VIDIOC_ENUM_FMT` / `FRAMESIZES` / `FRAMEINTERVALS`. Start picks the
Native Video Format nearest 1280×720 at 30 fps (ADR-0021), preferring
uncompressed fourccs. MJPEG is decoded with gdk-pixbuf. PipeWire camera
portal is not implemented in this slice; sandboxed hosts (Flatpak / Snap)
must grant the video device node. Mute-video substitutes black frames
with the graph still running. Camera-off stops the device. Missing or
denied camera does not fail `start()`. Runtime segmentation failure
after a successful blur/replace apply falls back to none and emits
`processorUnavailable` on EventChannel `flutter_ai_communications/events`
(ADR-0017). Apply-time unavailable is a typed `NativeProcessorResult`.
Selfie segmentation letterboxes into 256×256 (stretching 16:9 zeros the
mask), then unletterboxes alphas onto the frame.

Install `v4l-utils` on the Linux machine that collects receipts. The
graph is written for a Linux VM compile; device receipts are not
claimed from Windows.

## Screen send

Wayland is one system-picker source via xdg-desktop-portal ScreenCast.
After the portal Start result, frames come from PipeWire
(`libpipewire-0.3`). Install `libpipewire-0.3-dev` and `libspa-0.2-dev`
so CMake sets `FAC_HAS_PIPEWIRE` and the graph can pull frames. Without
those headers (or `libpipewire-0.3`), `startScreenShare` is unavailable
with reason `pipewire` and the portal is not shown. Unattended
`native_screen_test` skips the OS picker (`skipped=os-picker`). X11
enumerable capture remains for `XDG_SESSION_TYPE=x11` only.

Include sound (`includeSystemAudio`) is Pulse/PipeWire-Pulse loopback of
the current render sink's monitor source. It is not mixed into the mic
Capture stream. Mute still silences only the mic. Failure to open the
monitor leaves share video-only and Session status
`screenAudioUnavailable`.
