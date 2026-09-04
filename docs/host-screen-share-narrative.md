# Host narrative: Teams-style screen send

This library does not ship a picker. It ships a Screen source catalog,
Screen previews, a Share frame, and a Session start/stop for screen send.
The host builds the dialog. If this narrative cannot produce a Teams-like
share tray on enumerable desktops and an OS-picker fallback elsewhere, the
API failed.

The first host in this repo is `example/`. The in-session share control is
also the Orchestration e2e path. Product hosts copy the API usage, not
native graphs.

## What the page must do

After Join (meeting Session, Transport plugin attached), the user can:

1. Open Share. The host calls `beginScreenPick()` on the meeting Session.
2. See displays, windows, and All-displays as a grid of Screen previews
   (enumerable platforms). Metadata-only tiles if thumbs are denied.
3. Point at a tile. The host calls `indicateScreenSource(id)`. A red Share
   frame appears on the real display or window. Nothing is sent yet.
4. Optionally check Include sound, Optimize (Screen motion), cursor.
5. Confirm Share. The host calls `startScreenShare(id, …)` and
   `endScreenPick()`. Screen send starts. The Share frame stays on the
   sending source.
6. Keep the camera tile. Screen send is a second local Video surface. The
   host lays out both. The presenter may hide the local screen surface to
   avoid a hall of mirrors.
7. Toggle Include sound, Screen motion, and cursor while sending.
8. Stop sharing. `stopScreenShare()`. Camera send is unchanged.
9. Share a different source by opening the picker again, or by
   `startScreenShare` with a new id (replace).

Leave / Join does not share. Lobby lists `manager.screenSources()` as
names only. `beginScreenPick` and `startScreenShare` in lobby fail closed.

## Orchestration keys

Stable keys on the example Screen send subsection. flutter-skill and
`example/test/harness_test.dart` drive these. Native graph proof is
`example/integration_test/native_screen_test.dart` (no loopback wrap).

| Key | Control |
| --- | --- |
| `screen-session` | Start a meeting Session from idle |
| `screen-share` | `startScreenShare` on the indicated (or only) source |
| `screen-stop` | `stopScreenShare` |
| `screen-sound` | Include sound |
| `screen-motion` | Screen motion (Optimize) |
| `screen-cursor` | Cursor capture |
| `screen-source-<id>` | Indicate that Screen source |
| `screen-preview-<id>` | Screen preview thumb during pick |
| `screen-loopback` | Local send Video surface |
| `screen-status` | Last share result |

Join still uses `lobby-enter` / `lobby-join`. Share is in-session only.

## Enumerable desktop (Windows, macOS, Linux X11)

```text
sources = await manager.screenSources()
await meeting.beginScreenPick()
// host grid: session.screenPreview(id) per source
meeting.indicateScreenSource(hoveredId)
result = await meeting.startScreenShare(
  id,
  includeSystemAudio: includeSound,
  cursor: true,
  motion: optimize,
)
await meeting.endScreenPick()
// meeting.screenSurface is the send path; host may hide it
await meeting.setIncludeSystemAudio(true)   // live
await meeting.stopScreenShare()
```

The host never draws the Share frame. The library does.

Windows Store / MSIX hosts must declare `graphicsCaptureProgrammatic`
(and `graphicsCaptureWithoutBorder` to suppress the OS capture chrome)
in their own `Package.appxmanifest`. The plugin requests those
AppCapabilities at pick or share. Unpackaged Win32 uses Settings →
Privacy → Screen capture. See `packages/flutter_ai_communications_windows/README.md`.

## OS-picker platforms (web, Android, iOS, Linux Wayland)

```text
sources = await manager.screenSources()     // one system-picker source
result = await meeting.startScreenShare(sources.first.id)
// OS picker runs inside startScreenShare
await meeting.stopScreenShare()
```

`beginScreenPick`, Screen previews, and `indicateScreenSource` are no-ops.
The host still owns the Share button and the Include-sound / Optimize
controls that the Session API supports; the OS sheet may also offer audio.

iOS v1 presents ReplayKit `RPSystemBroadcastPickerView` on Share. Full-device
frames come from a Broadcast upload extension in the **host** app (example
ships `BroadcastUpload`) through an App Group into the same Texture handle
shape as camera send. In-app ReplayKit (`RPScreenRecorder`) is not
full-device share. Host Info.plist keys: `FacScreenShareExtension` and
`FacScreenShareAppGroup`. ScreenCaptureKit picker is not in the current
iOS SDK; use Broadcast until that ships.

## What the host must not do

- Persist a Screen preference or auto-share on Join.
- Mix system audio into the mic Capture stream or treat Mute as stopping
  computer sound.
- Camera-off in order to share, or stop share in order to open Camera
  preview.
- Import `RTCVideoView` / `dart:html` for the local screen surface.
- Treat an inbound presentation as a local Screen source. That is an
  inbound Video surface.
