# Host narrative: Teams- and Zoom-style lobby

This library does not ship a device picker. It ships catalogs, preference
resolution, Session, Camera preview, and Video surfaces. The host builds the
page. If this narrative cannot produce both a Teams-like and a Zoom-like lobby,
the API failed.

The first host in this repo is `example/`. That lobby subsection is also the
Orchestration e2e path. Product hosts copy the API usage, not native graphs.

## What the page must do

Before a meeting Transport exists, the user can:

1. See mode: audio only, video only, or AV.
2. Enter a **lobby Session** (`start()`, no Transport plugin). Permission is
   requested inside `start()` and waits.
3. Pick capture and render Endpoints from the audio catalog (live switch on
   that Session).
4. Pick a Camera Endpoint when the mode includes video. Self-view is the lobby
   Session’s Video surface, not Camera preview.
5. Mute (silence on the Capture stream). Lobby video is Camera-off or camera
   on, not Mute-video.
6. Run Test record: record Capture stream bytes, play them on the selected
   render Endpoint.
7. Leave without joining: `session.stop()`.
8. Join: read **Session settings**, `stop()` the lobby Session, `start()` a
   meeting Session with those settings, attach the Transport plugin (example:
   Echo Transport or the WebRTC plugin).

Zoom-like chrome: speaker, mic, and camera on one row under a large self-view.
Teams-like chrome: devices in a settings flyout beside a self-view. Both are
the same library calls. The example mimics the best of both: large self-view,
device picks, permission on enter, Join.

## Lobby is a Session

```text
manager.endpoints()
manager.cameras()                 // when the catalog exists
manager.bindPreference(...)
manager.bindCameraPreference(...)
result = await manager.start(
  purpose: 'lobby',
  direction: ...,                 // audio, video, or AV
  preference: ...,
  cameraPreference: ...,
)
// no Transport plugin
lobby.select(...)                 // audio live switch
lobby.selectCamera(id)            // when video exists; remotes do not exist
lobby.mute() / unmute()
lobby.setCameraEnabled(false)     // Camera-off in the lobby
settings = lobby.settings         // when the type exists; else host copies ids
await lobby.stop()
```

Do not start a second graph for lobby meters. The Capture stream is the meter.
Do not attach Echo Transport or a WebRTC plugin in the lobby.

## Join

```text
result = await manager.start(
  purpose: 'meeting',
  settings: settings,             // or equivalent start args copied from lobby
)
await session.attach Transport plugin / EchoTransport
```

Objects are not shared. A brief exclusive-device gap is allowed. Do not freeze
the last camera frame.

Audio-only join omits camera send. Later `enableVideo` on the same meeting
Session. Missing camera or camera denial does not fail start(); Session status
says video is not running. The host (proctoring vs optional camera) decides.

## In-call

| Control | Library call |
| --- | --- |
| Mic mute | `session.mute()` / unmute (silence frames) |
| Video mute / black tile | `session.muteVideo()` |
| Camera off / avatar | `session.setCameraEnabled(false)` |
| Flip camera | `session.selectCamera(id)` live switch |
| Camera settings | Camera-off, then Camera preview; host Apply/Cancel |
| Blur / replace | later plan; v1 processor is none |
| Speaker / headset | `session.selectRender(...)` live switch |
| Leave | `session.stop()` |
| Screen send | in-session only; `docs/host-screen-share-narrative.md` |

## Orchestration

Drive the **example lobby** on a real head: enter lobby → permission → pick
capture/render (and camera when present) → mute → Join → in-session mute /
Camera-off / flip / leave. Keys live on the lobby subsection and the meeting
subsection. That path is Orchestration. Do not call it Marionette.

## Persistence

The host stores Endpoint preference and Camera preference. The library never
writes them.

## Failure mapping

Host copy only:

- microphone denied / restricted (start failed when audio capture was requested)
- camera denied / restricted / none / no-mode (Session up; status says so)
- screen denied / none (Session up; status says so; never auto-share on Join)
- already-active Session (show the other purpose)
- processor unavailable (later: warn, stay on none)

No library strings.
