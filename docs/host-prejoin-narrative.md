# Host narrative: Teams- and Zoom-style landing page

This library does not ship a device picker. It ships catalogs, preference resolution, Pre-join preview, and Session controls. The host builds the page. If this narrative cannot produce both a Teams-like and a Zoom-like lobby, the API failed.

## What the page must do

Before a conversation exists, the user can:

1. See which mode this product entry point is: audio only, video only, or AV.
2. Pick capture and render audio Endpoints from the audio catalog.
3. Pick one camera from the Camera Endpoint catalog when the mode includes video.
4. See themselves on a Preview Texture when video is on.
5. Choose Video processor none, blur, or replace, and see it on that preview.
6. Mute-audio, Mute-video, or Camera-off in the lobby without creating a Session.
7. Join, which calls `start()` with the current picks.

Zoom-like chrome puts speaker, mic, and camera on one row under a large self-view. Teams-like chrome puts devices in a settings flyout beside a self-view. Both are the same library calls.

## Idle, before Session

```text
manager.endpoints()            // audio catalog, works idle
manager.cameras()              // camera catalog, works idle after permission
manager.bindPreference(...)    // host-persisted audio list
manager.bindCameraPreference(...)
preview = await manager.startPreview(
  videoFormat: ...,            // default 1280x720@30
  cameraId: ...,               // optional explicit pick
  processor: BlurVideoProcessor(intensity: 0.6)
  // or ReplaceVideoProcessor.bytes(...) / .asset(...)
)
preview.textureId             // Flutter Texture
preview.selectCamera(id)      // ephemeral, does not write preference
preview.setProcessor(...)
preview.setCameraEnabled(false)  // Camera-off in the lobby
await preview.stop()          // leaving the page without joining
```

Permission: `startPreview` requests camera (and mic if the host asked for meters) and waits. Denied is a typed result. Do not invent a second permission helper in product code if the manager already waits.

Audio meters on the landing page, if shown, subscribe to a short-lived preview meter or wait until Session. Do not start a full duplex Session just to draw a mic bar.

## Join

```text
result = await manager.start(
  direction: audioCapture + audioPlayback + videoCapture,
  captureFormat: ...,
  playbackFormat: ...,
  videoFormat: ...,
  preference: SessionPreference(...),          // audio
  cameraPreference: ...,                       // or explicit cameraId
  videoProcessor: preview.processor,
)
```

`start()` may override the preview camera. After `StartReady`, stop calling preview APIs; the Session now owns the Preview Texture. Promoting should not flicker if the camera and processor are unchanged.

Audio-only join omits video direction. Later:

```text
await session.enableVideo(cameraId: ..., videoFormat: ..., processor: ...)
await session.selectCamera(otherId)
await session.setVideoProcessor(...)
await session.muteVideo()       // black frames
await session.setCameraEnabled(false)  // hardware off
await session.pause()           // audio + video
```

## In-call controls both products need

| Control | Library call |
| --- | --- |
| Mic mute | `session.mute()` / unmute (silence frames) |
| Video mute / black tile | `session.muteVideo()` |
| Camera off / lens light out | `session.setCameraEnabled(false)` |
| Switch camera | `session.selectCamera(id)` |
| Blur / replace / none | `session.setVideoProcessor(...)` |
| Speaker / headset | `session.selectRender(...)` |
| Leave | `session.stop()` |

If a product needs a control that is not a row in this table, open a spec gap. Do not fake it in the host with a second camera plugin.

## Sinks

Attach after `StartReady` (or as soon as video is enabled):

```text
await session.attachSink(webRtcSink)   // companion package
// later: disk recorder, WebTransport
```

Local preview does not require a sink. `RTCVideoView` is optional extra after the WebRTC sink exists. The library Texture is the source of truth for “what I look like.”

## Persistence

The host stores audio Endpoint preference and Camera preference. The library never writes them. Lobby picks that should survive the next launch belong in host storage and are passed into `bindPreference` / `bindCameraPreference` or `start()`.

## Failure mapping

Map typed results to product copy only:

- microphone denied / restricted
- camera denied / restricted
- no usable camera
- already-active Session (show the other purpose)
- processor unavailable (keep Session, warn, fall back to none)

No library strings.
