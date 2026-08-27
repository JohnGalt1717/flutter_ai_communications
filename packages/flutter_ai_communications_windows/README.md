# flutter_ai_communications_windows

Windows adapter. Same Audio manager contract as the other federated
packages.

## How it talks to the OS

Dart FFI against WASAPI via `package:win32`:

- `IMMDeviceEnumerator` — catalog (capture / render Endpoints)
- Shared-mode `IAudioClient` with `AUTOCONVERTPCM` — PCM16 LE mono 24 kHz

## Host package (Store / MSIX)

This plugin cannot write the host `Package.appxmanifest`. Consent is
package-identity gated:

- **Unpackaged Win32** (`flutter run -d windows`, sideloaded `.exe`): no
  Store prompt. `start()` probes WASAPI. The user allows capture in
  Settings → Privacy → Microphone → “Let desktop apps access your
  microphone”.
- **Microsoft Store / MSIX** (process has package identity): `start()`
  requests `microphone` with first-party WinRT (`AppCapability` /
  `DeviceAccessInformation`) and waits for the consent UI. The host must
  declare the capability itself.

Required for capture Sessions:

```xml
<Capabilities>
  <DeviceCapability Name="microphone"/>
</Capabilities>
```

If you package with the `msix` tool:

```yaml
msix_config:
  capabilities: microphone
```

Optional Bluetooth identity. Packaged hosts that declare this get a
Store consent prompt; unpackaged Win32 enumerates remembered devices
with no extra UI. Denial must not block audio — the catalog keeps
WASAPI names and the known-profile registry falls back to those names.
Approve → Bluetooth alias + Class of Device (car audio, headset,
speaker) for Acoustic-profile matching, including fielded car head
units such as Tesla:

```xml
<DeviceCapability Name="bluetooth"/>
```

Unpackaged Win32 (the default `flutter run -d windows` binary) has no
manifest. Permission is Settings → Privacy → Microphone → “Let desktop
apps access your microphone”, plus any per-app prompt Windows shows.

## Gaps versus iOS / Android

These are documented limits, not bugs:

- **No Isolation.** Events are always `unavailable`.
  `openIsolationSettings()` is a no-op.
- **No handset Endpoint.** Built-in speakers and mics are
  `speakerphone`. Bluetooth / USB are `bluetooth` / `wired`.
- **Packaged microphone consent** is requested at `start()`. The host
  must declare `microphone` in its own manifest; this package cannot
  inject that file.
- **AEC / NS / AGC** are whatever the communications Endpoint
  already applies. The graph asks WASAPI for the communications
  stream category; it does not configure a vendor APO.
- **Quality is best-effort.** Endpoint switches restart the graph
  and emit a silence frame so the Session capture subscription
  survives (ADR-0004).
